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

variable "tags" {
  type    = map(string)
  default = {}
}
