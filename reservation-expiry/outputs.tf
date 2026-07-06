output "ecr_repository_url" {
  value = aws_ecr_repository.svc.repository_url
}

output "ecs_service_name" {
  value = aws_ecs_service.svc.name
}
