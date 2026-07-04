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

# ─── SECURITY GROUP — sin ingress ────────────────────────────────────────────
resource "aws_security_group" "ecs" {
  name        = "sgrp-ecs-${local.name}"
  description = "reservation-expiry ECS task - no inbound traffic"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to VPC endpoints"
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
      { name = "EXPIRY_QUEUE_URL", value = var.sqs_expiry_url },
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

# ─── ECS SERVICE — sin load balancer ─────────────────────────────────────────
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
