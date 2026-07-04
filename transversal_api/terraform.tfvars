env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id             = "vpc-078f9bb42db3ac7ac"
vpc_cidr           = "10.0.0.0/16"
private_subnet_ids = ["subnet-06cf0caa892d842d4", "subnet-0c9a77c077345ba3a"]

lambda_authorizer_invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:302780033379:function:lambda-auth-ticketing-co-dev/invocations"
lambda_authorizer_arn        = "arn:aws:lambda:us-east-1:302780033379:function:lambda-auth-ticketing-co-dev"

tags = {
  project = "ticketing-platform"
}
