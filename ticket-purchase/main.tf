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

# ─── DLQ para cola P ─────────────────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                      = "sqs-${var.capacity}-${var.country}-purchase-dlq-${var.env}"
  kms_master_key_id         = var.kms_sqs_arn
  message_retention_seconds = 1209600 # 14 días
  tags                      = local.resource_tags
}

# Redrive policy en la cola P (definida en ticket-reservation)
# Se aplica aquí via aws_sqs_queue_redrive_policy para no crear dependencia circular
resource "aws_sqs_queue_redrive_policy" "purchase" {
  queue_url = var.sqs_purchase_url
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# ─── SECURITY GROUP — sin ingress (solo consume SQS vía endpoint) ────────────
resource "aws_security_group" "ecs" {
  name        = "sgrp-ecs-${local.name}"
  description = "ticket-purchase ECS task - no inbound traffic"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to VPC endpoints (SQS, DynamoDB)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
    environment = [
      { name = "ENV", value = var.env },
      { name = "PURCHASE_QUEUE_URL", value = var.sqs_purchase_url },
      { name = "AWS_REGION", value = var.aws_region }
    ]
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

# ─── ECS SERVICE — sin load balancer (solo SQS consumer) ────────────────────
resource "aws_ecs_service" "svc" {
  name            = "svc-${local.name}"
  cluster         = var.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.svc.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [var.subnet_id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }

  tags = local.resource_tags
}
