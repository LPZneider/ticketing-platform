output "sqs_dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}
