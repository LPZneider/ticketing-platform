env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id             = "vpc-089a7b802dfd99dfc"
vpc_cidr           = "10.0.0.0/16"
private_subnet_ids = ["subnet-08cb91179be09c056", "subnet-060233ee75029b379"]

lambda_authorizer_invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:302780033379:function:lambda-auth-ticketing-co-dev/invocations"
lambda_authorizer_arn        = "arn:aws:lambda:us-east-1:302780033379:function:lambda-auth-ticketing-co-dev"

tags = {
  project = "ticketing-platform"
}
