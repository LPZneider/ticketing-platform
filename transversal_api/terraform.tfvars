env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

# Outputs de transversal_networking:
vpc_id             = "<transversal_networking.vpc_id>"
vpc_cidr           = "<transversal_networking.vpc_cidr>"
private_subnet_ids = [
  "<transversal_networking.private_subnet_ids[ticket-reservation]>",
  "<transversal_networking.private_subnet_ids[ticket-availability]>"
]

# Outputs de auth:
lambda_authorizer_invoke_arn = "<auth.lambda_auth_invoke_arn>"
lambda_authorizer_arn        = "<auth.lambda_auth_arn>"

tags = {
  project = "ticketing-platform"
}
