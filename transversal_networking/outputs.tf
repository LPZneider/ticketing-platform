output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnet_ids" {
  value = { for k, s in aws_subnet.private : k => s.id }
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "route_table_private_id" {
  value = aws_route_table.private.id
}

output "alb_secondary_subnet_id" {
  value = aws_subnet.alb_secondary.id
}
