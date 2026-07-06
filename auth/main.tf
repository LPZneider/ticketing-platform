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

# ─── SECRETS MANAGER — secretos del authorizer ──────────────────────────────
resource "aws_secretsmanager_secret" "auth" {
  name                    = local.secret_name
  description             = "Auth secrets for Lambda authorizer - ${var.env}"
  recovery_window_in_days = 7
  tags                    = local.resource_tags
}

# ─── IAM ROLE — Lambda authorizer ───────────────────────────────────────────
resource "aws_iam_role" "lambda_auth" {
  name = "role-lambda-auth-${var.capacity}-${var.country}-${var.env}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.resource_tags
}

# Managed policy para VPC access (ec2:CreateNetworkInterface, etc.)
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda_auth.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_auth" {
  name = "policy-lambda-auth-${var.env}"
  role = aws_iam_role.lambda_auth.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SecretsManagerRead"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.auth.arn]
      }
    ]
  })
}

# ─── SECURITY GROUP — Lambda en VPC ─────────────────────────────────────────
resource "aws_security_group" "lambda_auth" {
  name        = "sgrp-lambda-auth-${var.capacity}-${var.country}-${var.env}"
  description = "Lambda authorizer - egress only to VPC endpoints"
  vpc_id      = var.vpc_id

  egress {
    description = "HTTPS to VPC endpoints (Secrets Manager)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.resource_tags, { Name = "sg-lambda-auth-${var.capacity}-${var.country}-${var.env}" })
}

# ─── LAMBDA AUTHORIZER ───────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_auth" {
  name              = "/aws/lambda/lambda-auth-${var.capacity}-${var.country}-${var.env}"
  retention_in_days = 30
  tags              = local.resource_tags
}

resource "aws_lambda_function" "auth" {
  function_name = "lambda-auth-${var.capacity}-${var.country}-${var.env}"
  role          = aws_iam_role.lambda_auth.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  filename         = local.lambda_zip_path
  source_code_hash = local.lambda_zip_hash
  timeout       = 10
  memory_size   = 256

  environment {
    variables = {
      SECRET_NAME = local.secret_name
      ENV         = var.env
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda_auth.id]
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_auth,
    aws_iam_role_policy_attachment.lambda_vpc,
    aws_iam_role_policy.lambda_auth,
  ]

  tags = local.resource_tags
}
