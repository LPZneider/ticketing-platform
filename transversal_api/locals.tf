locals {
  resource_tags = merge(var.tags, {
    env      = var.env
    capacity = var.capacity
    country  = var.country
  })
}
