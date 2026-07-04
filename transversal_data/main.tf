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

# ─── KMS — cifrado DynamoDB ──────────────────────────────────────────────────
resource "aws_kms_key" "dynamodb" {
  description             = "KMS key for DynamoDB tables - ${var.capacity}-${var.country}-${var.env}"
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
        Sid    = "AllowDynamoDB"
        Effect = "Allow"
        Principal = {
          Service = "dynamodb.amazonaws.com"
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

  tags = merge(local.resource_tags, { Name = "key-${var.capacity}-${var.country}-dynamodb-${var.env}" })
}

resource "aws_kms_alias" "dynamodb" {
  name          = "alias/key-${var.capacity}-${var.country}-dynamodb-${var.env}"
  target_key_id = aws_kms_key.dynamodb.key_id
}

# ─── DYNAMODB — tabla de tickets (inventario + estado) ──────────────────────
# Hash key: ticketId | Range key: eventType
# Conditional writes / optimistic locking via version attribute
resource "aws_dynamodb_table" "tickets" {
  name         = "table-${var.capacity}-${var.country}-tickets-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "ticketId"
  range_key    = "eventType"

  attribute {
    name = "ticketId"
    type = "S"
  }

  attribute {
    name = "eventType"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  # GSI para consultar por estado (ticket-availability-service)
  global_secondary_index {
    name            = "idx_status"
    hash_key        = "status"
    range_key       = "ticketId"
    projection_type = "ALL"
  }

  # TTL para expirar reservas automáticamente como respaldo
  ttl {
    attribute_name = "expiration_time"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.resource_tags, { Name = "table-${var.capacity}-${var.country}-tickets-${var.env}" })
}

# ─── DYNAMODB — tabla de órdenes (historial de compras) ─────────────────────
resource "aws_dynamodb_table" "orders" {
  name         = "table-${var.capacity}-${var.country}-orders-${var.env}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"
  range_key    = "timestamp"

  attribute {
    name = "orderId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.dynamodb.arn
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.resource_tags, { Name = "table-${var.capacity}-${var.country}-orders-${var.env}" })
}
