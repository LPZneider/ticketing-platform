output "lambda_auth_arn" {
  value = aws_lambda_function.auth.arn
}

output "lambda_auth_invoke_arn" {
  value = aws_lambda_function.auth.invoke_arn
}

output "secret_auth_arn" {
  value = aws_secretsmanager_secret.auth.arn
}
