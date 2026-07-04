locals {
  svc  = "reservation-expiry"
  name = "${var.capacity}-${var.country}-${local.svc}-${var.env}"

  tickets_table_name = element(split("/", var.tickets_table_arn), 1)
  expiry_queue_name  = element(split("/", var.sqs_expiry_url), 4)

  resource_tags = merge(var.tags, {
    env      = var.env
    capacity = var.capacity
    country  = var.country
    service  = local.svc
  })
}
