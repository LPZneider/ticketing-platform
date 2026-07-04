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

# ─── KMS compartido para todas las SQS ──────────────────────────────────────
resource "aws_kms_key" "sqs" {
  description             = "KMS key for SQS queues - ${var.capacity}-${var.country}-${var.env}"
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
        Sid    = "AllowSQS"
        Effect = "Allow"
        Principal = {
          Service = "sqs.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.resource_tags, { Name = "key-${var.capacity}-${var.country}-sqs-${var.env}" })
}

resource "aws_kms_alias" "sqs" {
  name          = "alias/key-${var.capacity}-${var.country}-sqs-${var.env}"
  target_key_id = aws_kms_key.sqs.key_id
}
