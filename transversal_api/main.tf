terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ─── SECURITY GROUP — internal NLB ─────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "sgrp-nlb-${var.capacity}-${var.country}-${var.env}"
  description = "NLB internal - allows API Gateway VPC Link traffic"
  vpc_id      = var.vpc_id

  ingress {
    description = "TCP from VPC Link (reservation)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "TCP from VPC Link (availability)"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "TCP to ECS tasks (reservation)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "TCP to ECS tasks (availability)"
    from_port   = 8081
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Ephemeral ports for health check responses"
    from_port   = 1024
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.resource_tags, { Name = "sg-nlb-${var.capacity}-${var.country}-${var.env}" })
}

# ─── INTERNAL NLB (REST API Gateway VPC Link only supports NLB) ────────────
resource "aws_lb" "main" {
  name               = "nlb-${var.capacity}-${var.country}-${var.env}"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  enable_deletion_protection         = false
  enable_cross_zone_load_balancing   = true
  enforce_security_group_inbound_rules_on_private_link_traffic = "off"

  tags = merge(local.resource_tags, { Name = "nlb-${var.capacity}-${var.country}-${var.env}" })
}

# ─── TARGET GROUPS — one per HTTP service ──────────────────────────────────
resource "aws_lb_target_group" "reservation" {
  name        = "tg-reservation-${var.env}"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.resource_tags
}

resource "aws_lb_target_group" "availability" {
  name        = "tg-availability-${var.env}"
  port        = 8080
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol            = "HTTP"
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.resource_tags
}

# ─── NLB LISTENERS — one port per service (method-based routing in API GW) ──
# Port 8080 → ticket-reservation (POST /events, POST /purchases)
resource "aws_lb_listener" "reservation" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reservation.arn
  }

  tags = local.resource_tags
}

# Port 8081 → ticket-availability (GET /events, GET /events/{id}/availability, GET /orders/{id})
resource "aws_lb_listener" "availability" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8081
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.availability.arn
  }

  tags = local.resource_tags
}

# ─── VPC LINK (API Gateway → NLB) ───────────────────────────────────────────
resource "aws_api_gateway_vpc_link" "main" {
  name        = "vpclink-${var.capacity}-${var.country}-${var.env}"
  target_arns = [aws_lb.main.arn]
  tags        = local.resource_tags
}

# ─── API GATEWAY REST ────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "main" {
  name        = "api-${var.capacity}-${var.country}-${var.env}"
  description = "Ticketing Platform API - ${var.env}"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.resource_tags
}

# ─── REQUEST AUTHORIZER (Lambda) ────────────────────────────────────────────
# REQUEST type: Lambda receives the full event (headers, path, method),
# allowing it to inspect methodArn to enforce admin restriction on POST /events.
# The returned context (userId, userRole) is forwarded to the backend
# via request_parameters in each integration.
resource "aws_api_gateway_authorizer" "lambda" {
  name                             = "lambda-auth-${var.capacity}-${var.env}"
  rest_api_id                      = aws_api_gateway_rest_api.main.id
  authorizer_uri                   = var.lambda_authorizer_invoke_arn
  authorizer_result_ttl_in_seconds = 300
  type                             = "REQUEST"
  identity_source                  = "method.request.header.Authorization"
}

resource "aws_lambda_permission" "apigw_invoke_authorizer" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_authorizer_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

# ─── API RESOURCES ────────────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "api" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_resource" "v1" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.api.id
  path_part   = "v1"
}

resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "events"
}

resource "aws_api_gateway_resource" "event_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.events.id
  path_part   = "{eventId}"
}

resource "aws_api_gateway_resource" "event_availability" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.event_id.id
  path_part   = "availability"
}

resource "aws_api_gateway_resource" "purchases" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "purchases"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.v1.id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "order_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{orderId}"
}

resource "aws_api_gateway_resource" "order_status" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.order_id.id
  path_part   = "status"
}

# ─── POST /events (admin) → ticket-reservation-service ───────────────────────────────────────────
resource "aws_api_gateway_method" "events_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_integration" "events_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.events_post.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "http://${aws_lb.main.dns_name}:8080/api/v1/events"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id
  request_parameters = {
    "integration.request.header.X-User-Id"   = "context.authorizer.userId"
    "integration.request.header.X-User-Role" = "context.authorizer.userRole"
  }
}

# ─── GET /events → ticket-availability-service ───────────────────────────────
resource "aws_api_gateway_method" "events_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.events.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_integration" "events_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.events.id
  http_method             = aws_api_gateway_method.events_get.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "http://${aws_lb.main.dns_name}:8081/api/v1/events"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id
  request_parameters = {
    "integration.request.header.X-User-Id"   = "context.authorizer.userId"
    "integration.request.header.X-User-Role" = "context.authorizer.userRole"
  }
}

# ─── GET /events/{eventId}/availability → ticket-availability-service ─────────
resource "aws_api_gateway_method" "event_availability_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.event_availability.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.path.eventId"         = true
  }
}

resource "aws_api_gateway_integration" "event_availability_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.event_availability.id
  http_method             = aws_api_gateway_method.event_availability_get.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "http://${aws_lb.main.dns_name}:8081/api/v1/events/{eventId}/availability"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id
  request_parameters = {
    "integration.request.path.eventId"        = "method.request.path.eventId"
    "integration.request.header.X-User-Id"   = "context.authorizer.userId"
    "integration.request.header.X-User-Role" = "context.authorizer.userRole"
  }
}

# ─── POST /purchases → ticket-reservation-service ─────────────────────────────
resource "aws_api_gateway_method" "purchases_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.purchases.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
  request_parameters = {
    "method.request.header.Authorization" = true
  }
}

resource "aws_api_gateway_integration" "purchases_post" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.purchases.id
  http_method             = aws_api_gateway_method.purchases_post.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "POST"
  uri                     = "http://${aws_lb.main.dns_name}:8080/api/v1/purchases"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id
  request_parameters = {
    "integration.request.header.X-User-Id"   = "context.authorizer.userId"
    "integration.request.header.X-User-Role" = "context.authorizer.userRole"
  }
}

# ─── GET /orders/{orderId} → ticket-availability-service ──────────────────────
resource "aws_api_gateway_method" "orders_id_get" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.order_status.id
  http_method   = "GET"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.lambda.id
  request_parameters = {
    "method.request.header.Authorization" = true
    "method.request.path.orderId"         = true
  }
}

resource "aws_api_gateway_integration" "orders_id_get" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.order_status.id
  http_method             = aws_api_gateway_method.orders_id_get.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "http://${aws_lb.main.dns_name}:8081/api/v1/orders/{orderId}/status"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.main.id
  request_parameters = {
    "integration.request.path.orderId"        = "method.request.path.orderId"
    "integration.request.header.X-User-Id"   = "context.authorizer.userId"
    "integration.request.header.X-User-Role" = "context.authorizer.userRole"
  }
}

# ─── DEPLOYMENT + STAGE ─────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_method.events_post,
      aws_api_gateway_method.events_get,
      aws_api_gateway_method.event_availability_get,
      aws_api_gateway_method.purchases_post,
      aws_api_gateway_method.orders_id_get,
      aws_api_gateway_integration.events_post,
      aws_api_gateway_integration.events_get,
      aws_api_gateway_integration.event_availability_get,
      aws_api_gateway_integration.purchases_post,
      aws_api_gateway_integration.orders_id_get,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.env

  tags = local.resource_tags
}

# ─── WAF WebACL associated to stage ────────────────────────────────────────
resource "aws_wafv2_web_acl" "main" {
  name  = "waf-${var.capacity}-${var.country}-${var.env}"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesCommonRuleSetMetric"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSManagedRulesKnownBadInputsMetric"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "waf-${var.capacity}-${var.country}-${var.env}"
    sampled_requests_enabled   = true
  }

  tags = local.resource_tags
}

resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_api_gateway_stage.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
