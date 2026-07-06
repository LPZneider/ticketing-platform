env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id             = "vpc-089a7b802dfd99dfc"
vpc_cidr           = "10.0.0.0/16"
private_subnet_ids = ["subnet-08cb91179be09c056"]
lambda_source_dir = "/home/neider/Documents/prueba/ticketing-platform/../lambda-auth/src"

tags = {
  project = "ticketing-platform"
}
