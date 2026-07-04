variable "env" {
  type     = string
  nullable = false
}

variable "capacity" {
  type     = string
  nullable = false
}

variable "country" {
  type     = string
  nullable = false
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_id" {
  type     = string
  nullable = false
}

variable "private_subnet_ids" {
  type     = list(string)
  nullable = false
}

variable "vpc_cidr" {
  type     = string
  nullable = false
}

variable "lambda_source_dir" {
  description = "Path al directorio src/ del repo lambda-auth clonado localmente"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
