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

variable "lambda_zip_path" {
  description = "Path local al ZIP del Lambda authorizer"
  type        = string
  default     = "lambda_auth.zip"
}

variable "tags" {
  type    = map(string)
  default = {}
}
