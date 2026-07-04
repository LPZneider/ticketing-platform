output "sqs_purchase_arn" {
  value = aws_sqs_queue.purchase.arn
}

output "sqs_purchase_url" {
  value = aws_sqs_queue.purchase.url
}

output "sqs_expiry_arn" {
  value = aws_sqs_queue.expiry.arn
}

output "sqs_expiry_url" {
  value = aws_sqs_queue.expiry.url
}

output "sg_ecs_id" {
  value = aws_security_group.ecs.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.svc.repository_url
}

output "ecs_service_name" {
  value = aws_ecs_service.svc.name
}
