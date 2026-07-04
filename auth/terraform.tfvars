env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

# Outputs de transversal_networking:
# terraform -chdir=../transversal_networking output vpc_id
vpc_id = "<transversal_networking.vpc_id>"

# terraform -chdir=../transversal_networking output vpc_cidr
vpc_cidr = "<transversal_networking.vpc_cidr>"

# terraform -chdir=../transversal_networking output -json private_subnet_ids
# Usar cualquiera de las subnets del mapa, ej: private_subnet_ids["ticket-reservation"]
private_subnet_ids = ["<transversal_networking.private_subnet_ids[ticket-reservation]>"]

lambda_zip_path = "lambda_auth.zip"

tags = {
  project = "ticketing-platform"
}
