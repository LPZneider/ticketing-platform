variable "env" { type = string }
variable "capacity" { type = string }
variable "country" { type = string }
variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_id" { type = string }

variable "ecs_cluster_arn" { type = string }
variable "sqs_expiry_arn" {
  description = "ARN de la cola R (output de ticket-reservation)"
  type = string
}
variable "sqs_expiry_url" { type = string }

variable "kms_sqs_arn" { type = string }
variable "kms_dynamodb_arn" { type = string }
variable "tickets_table_arn" { type = string }

variable "container_image" {
  type = string
  default = "nginx:latest"
}
variable "desired_count" {
  type = number
  default = 1
}
variable "cpu" {
  type = number
  default = 256
}
variable "memory" {
  type = number
  default = 512
}

variable "tags" {
  type    = map(string)
  default = {}
}
