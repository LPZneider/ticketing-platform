env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id    = "vpc-078f9bb42db3ac7ac"
vpc_cidr  = "10.0.0.0/16"
subnet_id = "subnet-0e43626f22b2c9e86"

ecs_cluster_arn  = "arn:aws:ecs:us-east-1:302780033379:cluster/ecs-ticketing-co-dev"
sqs_purchase_arn = "arn:aws:sqs:us-east-1:302780033379:sqs-ticketing-co-purchase-requests-dev"
sqs_purchase_url = "https://sqs.us-east-1.amazonaws.com/302780033379/sqs-ticketing-co-purchase-requests-dev"

kms_sqs_arn       = "arn:aws:kms:us-east-1:302780033379:key/d38ffd17-2dc8-43b7-87eb-94e947fcd4f9"
kms_dynamodb_arn  = "arn:aws:kms:us-east-1:302780033379:key/220ed17a-789b-4f6a-8537-cfefe3812092"
tickets_table_arn = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-tickets-dev"
orders_table_arn  = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-orders-dev"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 512
memory          = 1024

tags = { project = "ticketing-platform" }
