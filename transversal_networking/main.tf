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

# ─── VPC ────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.resource_tags, { Name = "vpc-${var.capacity}-${var.country}-${var.env}" })
}

# ─── SUBNETS PRIVADAS (una por servicio) ────────────────────────────────────
resource "aws_subnet" "private" {
  for_each          = var.subnet_cidrs
  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "${var.aws_region}a"
  tags              = merge(local.resource_tags, { Name = "subnet-${var.capacity}-${var.country}-${each.key}-${var.env}" })
}

# ─── ROUTE TABLE PRIVADA ────────────────────────────────────────────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.resource_tags, { Name = "rt-private-${var.capacity}-${var.country}-${var.env}" })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# ─── VPC GATEWAY ENDPOINT — DynamoDB (sin NAT) ──────────────────────────────
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = merge(local.resource_tags, { Name = "vpce-dynamodb-${var.capacity}-${var.country}-${var.env}" })
}

# ─── VPC INTERFACE ENDPOINT — SQS ───────────────────────────────────────────
resource "aws_security_group" "vpce_sqs" {
  name        = "sgrp-vpce-sqs-${var.capacity}-${var.country}-${var.env}"
  description = "Allow HTTPS from VPC to SQS endpoint"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "HTTPS to VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(local.resource_tags, { Name = "sg-vpce-sqs-${var.capacity}-${var.country}-${var.env}" })
}

resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private["ticket-reservation"].id]
  security_group_ids  = [aws_security_group.vpce_sqs.id]
  private_dns_enabled = true
  tags                = merge(local.resource_tags, { Name = "vpce-sqs-${var.capacity}-${var.country}-${var.env}" })
}

# ─── VPC INTERFACE ENDPOINT — Secrets Manager (para Lambda auth) ────────────
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private["ticket-reservation"].id]
  security_group_ids  = [aws_security_group.vpce_sqs.id]
  private_dns_enabled = true
  tags                = merge(local.resource_tags, { Name = "vpce-secretsmanager-${var.capacity}-${var.country}-${var.env}" })
}

# ─── VPC INTERFACE ENDPOINT — ECR (para ECS Fargate pull de imágenes) ───────
resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private["ticket-reservation"].id]
  security_group_ids  = [aws_security_group.vpce_sqs.id]
  private_dns_enabled = true
  tags                = merge(local.resource_tags, { Name = "vpce-ecr-api-${var.capacity}-${var.country}-${var.env}" })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private["ticket-reservation"].id]
  security_group_ids  = [aws_security_group.vpce_sqs.id]
  private_dns_enabled = true
  tags                = merge(local.resource_tags, { Name = "vpce-ecr-dkr-${var.capacity}-${var.country}-${var.env}" })
}

# ─── SUBNET SECUNDARIA EN us-east-1b (requisito ALB >= 2 AZs) ───────────────
resource "aws_subnet" "alb_secondary" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region}b"
  tags              = merge(local.resource_tags, { Name = "subnet-${var.capacity}-${var.country}-alb-b-${var.env}" })
}

resource "aws_route_table_association" "alb_secondary" {
  subnet_id      = aws_subnet.alb_secondary.id
  route_table_id = aws_route_table.private.id
}
