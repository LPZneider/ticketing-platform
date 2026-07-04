env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id    = "vpc-078f9bb42db3ac7ac"
vpc_cidr  = "10.0.0.0/16"
subnet_id = "subnet-06cf0caa892d842d4"
sg_alb_id = "sg-015c3e11d7d5c6639"

ecs_cluster_arn    = "arn:aws:ecs:us-east-1:302780033379:cluster/ecs-ticketing-co-dev"
ecs_cluster_name   = "ecs-ticketing-co-dev"
tg_reservation_arn = "arn:aws:elasticloadbalancing:us-east-1:302780033379:targetgroup/tg-reservation-dev/cd51b13bb9874643"

kms_sqs_arn       = "arn:aws:kms:us-east-1:302780033379:key/d38ffd17-2dc8-43b7-87eb-94e947fcd4f9"
kms_dynamodb_arn  = "arn:aws:kms:us-east-1:302780033379:key/220ed17a-789b-4f6a-8537-cfefe3812092"
tickets_table_arn = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-tickets-dev"
orders_table_arn  = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-orders-dev"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 512
memory          = 1024

tags = { project = "ticketing-platform" }
