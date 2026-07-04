output "ecs_cluster_arn" {
  value = aws_ecs_cluster.main.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "kms_ecs_logs_arn" {
  value = aws_kms_key.ecs_logs.arn
}
