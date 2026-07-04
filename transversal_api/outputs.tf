output "api_gateway_id" {
  value = aws_api_gateway_rest_api.main.id
}

output "api_gateway_execution_arn" {
  value = aws_api_gateway_rest_api.main.execution_arn
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "alb_dns_name" {
  value = aws_lb.main.dns_name
}

output "tg_reservation_arn" {
  value = aws_lb_target_group.reservation.arn
}

output "tg_availability_arn" {
  value = aws_lb_target_group.availability.arn
}

output "sg_alb_id" {
  value = aws_security_group.alb.id
}
