output "kms_sqs_arn" {
  value = aws_kms_key.sqs.arn
}

output "kms_sqs_alias" {
  value = aws_kms_alias.sqs.name
}
