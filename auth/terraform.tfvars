env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id             = "vpc-078f9bb42db3ac7ac"
vpc_cidr           = "10.0.0.0/16"
private_subnet_ids = ["subnet-06cf0caa892d842d4"]
lambda_source_dir  = "/Users/lpzneider/Documents/lambda-auth/src"

tags = {
  project = "ticketing-platform"
}
