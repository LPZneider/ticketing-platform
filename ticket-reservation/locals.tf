locals {
  svc  = "ticket-reservation"
  name = "${var.capacity}-${var.country}-${local.svc}-${var.env}"

  resource_tags = merge(var.tags, {
    env         = var.env
    capacity    = var.capacity
    country     = var.country
    service     = local.svc
  })
}
