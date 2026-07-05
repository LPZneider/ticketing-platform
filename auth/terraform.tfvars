env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id             = "vpc-07a79279c9c1afaa3"
vpc_cidr           = "10.0.0.0/16"
private_subnet_ids = ["subnet-0f026d2e9549aa112"]
lambda_source_dir  = "/Users/lpzneider/Documents/ticketing-platform/../lambda-auth/src"

tags = {
  project = "ticketing-platform"
}
