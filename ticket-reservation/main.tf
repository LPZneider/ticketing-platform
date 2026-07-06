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

# ─── SQS "P" — purchase-requests ────────────────────────────────────────────
resource "aws_sqs_queue" "purchase" {
  name                       = "sqs-${var.capacity}-${var.country}-purchase-requests-${var.env}"
  kms_master_key_id          = var.kms_sqs_arn
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 30
  tags                       = local.resource_tags
}

# ─── SQS "R" — reservation-expiry ──────────────────────────────────────────
# delay_seconds is set on the queue (not on the message) intentionally:
# all messages inherit the queue delay without the producer needing to set it.
# The producer MUST NOT send DelaySeconds per message on this queue
# to avoid stacking delays (SQS max: 900 s).
resource "aws_sqs_queue" "expiry" {
  name                       = "sqs-${var.capacity}-${var.country}-reservation-expiry-${var.env}"
  kms_master_key_id          = var.kms_sqs_arn
  delay_seconds              = 180
  message_retention_seconds  = 3600
  visibility_timeout_seconds = 30
  tags                       = local.resource_tags
}

# ─── SECURITY GROUP — ECS task ───────────────────────────────────────────────
resource "aws_security_group" "ecs" {
  name        = "sgrp-ecs-${local.name}"
  description = "ticket-reservation ECS task"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from NLB (source IP preserved)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to VPC endpoints (SQS, DynamoDB)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description     = "HTTPS to S3 (ECR layer blobs via gateway endpoint)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_prefix_list.s3.id]
  }

  egress {
    description     = "HTTPS to DynamoDB (gateway endpoint)"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [data.aws_prefix_list.dynamodb.id]
  }

  tags = merge(local.resource_tags, { Name = "sg-ecs-${local.name}" })
}

# ─── CLOUDWATCH LOG GROUP ────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "svc" {
  name              = "/ecs/${local.name}"
  retention_in_days = 30
  tags              = local.resource_tags
}

# ─── ECS TASK DEFINITION ─────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "svc" {
  family                   = local.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = local.svc
    image     = var.container_image
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "ENV", value = var.env },
      { name = "AWS_REGION", value = var.aws_region },
      { name = "TICKETS_TABLE_NAME", value = local.tickets_table_name },
      { name = "ORDERS_TABLE_NAME", value = local.orders_table_name },
      { name = "AWS_DYNAMODB_ENDPOINT", value = "https://dynamodb.${var.aws_region}.amazonaws.com" },
      { name = "PURCHASE_QUEUE_URL", value = aws_sqs_queue.purchase.url },
      { name = "PURCHASE_QUEUE_NAME", value = aws_sqs_queue.purchase.name },
      { name = "EXPIRY_QUEUE_URL", value = aws_sqs_queue.expiry.url },
      { name = "EXPIRY_QUEUE_NAME", value = aws_sqs_queue.expiry.name }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8080/actuator/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 60
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.svc.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])

  tags = local.resource_tags
}

# ─── ECS SERVICE ─────────────────────────────────────────────────────────────
resource "aws_ecs_service" "svc" {
  name                               = "svc-${local.name}"
  cluster                            = var.ecs_cluster_arn
  task_definition                    = aws_ecs_task_definition.svc.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 120

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.tg_reservation_arn
    container_name   = local.svc
    container_port   = 8080
  }

  tags = local.resource_tags
}
