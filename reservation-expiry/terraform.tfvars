env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id    = "vpc-089a7b802dfd99dfc"
vpc_cidr  = "10.0.0.0/16"
subnet_id = "subnet-038cdbbb367b2c8bc"

ecs_cluster_arn  = "arn:aws:ecs:us-east-1:302780033379:cluster/ecs-ticketing-co-dev"
sqs_expiry_arn   = "arn:aws:sqs:us-east-1:302780033379:sqs-ticketing-co-reservation-expiry-dev"
sqs_expiry_url   = "https://sqs.us-east-1.amazonaws.com/302780033379/sqs-ticketing-co-reservation-expiry-dev"

kms_sqs_arn       = "arn:aws:kms:us-east-1:302780033379:key/314954f2-d681-4d36-97eb-e664c71a287d"
kms_dynamodb_arn  = "arn:aws:kms:us-east-1:302780033379:key/2e4638d9-fd13-49a1-99b1-e52dba5278f5"
tickets_table_arn = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-tickets-dev"
orders_table_arn  = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-orders-dev"

container_image = "302780033379.dkr.ecr.us-east-1.amazonaws.com/ecr-ticketing-co-reservation-expiry-dev:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
