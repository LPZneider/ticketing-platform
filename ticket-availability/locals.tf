locals {
  svc  = "ticket-availability"
  name = "${var.capacity}-${var.country}-${local.svc}-${var.env}"

  tickets_table_name = element(split("/", var.tickets_table_arn), 1)

  resource_tags = merge(var.tags, {
    env      = var.env
    capacity = var.capacity
    country  = var.country
    service  = local.svc
  })
}
