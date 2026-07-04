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

variable "lambda_authorizer_invoke_arn" {
  description = "Invoke ARN of the Lambda authorizer (output from auth component)"
  type        = string
  nullable    = false
}

variable "lambda_authorizer_arn" {
  description = "ARN of the Lambda authorizer function"
  type        = string
  nullable    = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
