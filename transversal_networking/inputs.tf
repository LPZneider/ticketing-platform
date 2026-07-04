variable "env" {
  type     = string
  nullable = false
  validation {
    condition     = contains(["dev", "qa", "pdn"], var.env)
    error_message = "Only 'dev', 'qa', 'pdn' are allowed."
  }
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

variable "vpc_cidr" {
  type     = string
  nullable = false
}

variable "subnet_cidrs" {
  description = "Map of subnet name -> CIDR. One per service."
  type        = map(string)
  nullable    = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
