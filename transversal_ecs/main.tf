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

# ─── KMS para logs del cluster ECS ──────────────────────────────────────────
resource "aws_kms_key" "ecs_logs" {
  description             = "KMS key for ECS cluster logs - ${var.capacity}-${var.country}-${var.env}"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountAdmin"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.resource_tags, { Name = "key-${var.capacity}-${var.country}-ecs-logs-${var.env}" })
}

resource "aws_kms_alias" "ecs_logs" {
  name          = "alias/key-${var.capacity}-${var.country}-ecs-logs-${var.env}"
  target_key_id = aws_kms_key.ecs_logs.key_id
}

# ─── ECS CLUSTER compartido (Fargate) ───────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "ecs-${var.capacity}-${var.country}-${var.env}"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.ecs_logs.arn
      logging    = "OVERRIDE"
      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs_cluster.name
      }
    }
  }

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.resource_tags, { Name = "ecs-${var.capacity}-${var.country}-${var.env}" })
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 1
  }
}

resource "aws_cloudwatch_log_group" "ecs_cluster" {
  name              = "/ecs/cluster/${var.capacity}-${var.country}-${var.env}"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.ecs_logs.arn
  tags              = local.resource_tags
}
