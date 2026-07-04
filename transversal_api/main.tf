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

# ─── SECURITY GROUP — ALB interno ───────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "sg-alb-${var.capacity}-${var.country}-${var.env}"
  description = "ALB internal - only from API Gateway VPC Link"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from VPC Link"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTP to ECS tasks"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.resource_tags, { Name = "sg-alb-${var.capacity}-${var.country}-${var.env}" })
}

# ─── ALB INTERNO ────────────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "alb-${var.capacity}-${var.country}-${var.env}"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.private_subnet_ids

  # Acceso a logs deshabilitado en dev; habilitar en pdn con bucket S3
  enable_deletion_protection = false

  tags = merge(local.resource_tags, { Name = "alb-${var.capacity}-${var.country}-${var.env}" })
}

# ─── TARGET GROUPS — uno por servicio HTTP ──────────────────────────────────
resource "aws_lb_target_group" "reservation" {
  name        = "tg-reservation-${var.env}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
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
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/actuator/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = local.resource_tags
}

# ─── LISTENER ALB ───────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"not found\"}"
      status_code  = "404"
    }
  }

  tags = local.resource_tags
}

# POST /events → ticket-reservation-service (requiere rol admin en el authorizer)
resource "aws_lb_listener_rule" "events_post" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reservation.arn
  }

  condition {
    path_pattern { values = ["/events"] }
  }
  condition {
    http_request_method { values = ["POST"] }
  }
}

# POST /purchases → ticket-reservation-service
resource "aws_lb_listener_rule" "purchases_post" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.reservation.arn
  }

  condition {
    path_pattern { values = ["/purchases"] }
  }
  condition {
    http_request_method { values = ["POST"] }
  }
}

# GET /events y GET /events/{eventId}/availability → ticket-availability-service
resource "aws_lb_listener_rule" "events_get" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.availability.arn
  }

  condition {
    path_pattern { values = ["/events", "/events/*"] }
  }
  condition {
    http_request_method { values = ["GET"] }
  }
}

# GET /orders/{orderId} → ticket-availability-service
resource "aws_lb_listener_rule" "orders_get" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 40

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.availability.arn
  }

  condition {
    path_pattern { values = ["/orders/*"] }
  }
  condition {
    http_request_method { values = ["GET"] }
  }
}

# ─── VPC LINK (API Gateway → ALB) ───────────────────────────────────────────
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

# ─── AUTHORIZER REQUEST (Lambda) ─────────────────────────────────────────────
# Tipo REQUEST: el Lambda recibe el evento completo (headers, path, método),
# lo que permite que inspeccione el methodArn para aplicar restricción de admin
# en POST /events. El contexto devuelto (userId, userRole) se propaga al backend
# via request_parameters en cada integración.
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

# ─── RECURSOS API ─────────────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "events" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
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
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "purchases"
}

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "orders"
}

resource "aws_api_gateway_resource" "order_id" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_resource.orders.id
  path_part   = "{orderId}"
}

# ─── POST /events (admin) → ticket-reservation-service ───────────────────────
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
  uri                     = "http://${aws_lb.main.dns_name}/events"
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
  uri                     = "http://${aws_lb.main.dns_name}/events"
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
  uri                     = "http://${aws_lb.main.dns_name}/events/{eventId}/availability"
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
  uri                     = "http://${aws_lb.main.dns_name}/purchases"
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
  resource_id   = aws_api_gateway_resource.order_id.id
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
  resource_id             = aws_api_gateway_resource.order_id.id
  http_method             = aws_api_gateway_method.orders_id_get.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "http://${aws_lb.main.dns_name}/orders/{orderId}"
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

# ─── WAF WebACL asociado al stage ───────────────────────────────────────────
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
