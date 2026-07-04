output "kms_dynamodb_arn" {
  value = aws_kms_key.dynamodb.arn
}

output "kms_dynamodb_alias" {
  value = aws_kms_alias.dynamodb.name
}

output "tickets_table_arn" {
  value = aws_dynamodb_table.tickets.arn
}

output "tickets_table_name" {
  value = aws_dynamodb_table.tickets.name
}

output "orders_table_arn" {
  value = aws_dynamodb_table.orders.arn
}

output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}
