locals {
  svc  = "ticket-reservation"
  name = "${var.capacity}-${var.country}-${local.svc}-${var.env}"

  tickets_table_name = element(split("/", var.tickets_table_arn), 1)
  orders_table_name  = element(split("/", var.orders_table_arn), 1)

  resource_tags = merge(var.tags, {
    env         = var.env
    capacity    = var.capacity
    country     = var.country
    service     = local.svc
  })
}
