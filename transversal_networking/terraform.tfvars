env      = "dev"
capacity = "ticketing"
country  = "co"
vpc_cidr = "10.0.0.0/16"

subnet_cidrs = {
  ticket-reservation   = "10.0.1.0/24"
  ticket-purchase      = "10.0.2.0/24"
  reservation-expiry   = "10.0.3.0/24"
  ticket-availability  = "10.0.4.0/24"
}

tags = {
  project = "ticketing-platform"
}
