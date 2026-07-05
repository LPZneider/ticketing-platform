env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

vpc_id    = "vpc-078f9bb42db3ac7ac"
vpc_cidr  = "10.0.0.0/16"
subnet_id = "subnet-010ec08720d47a421"
sg_alb_id = "sg-015c3e11d7d5c6639"

ecs_cluster_arn     = "arn:aws:ecs:us-east-1:302780033379:cluster/ecs-ticketing-co-dev"
tg_availability_arn = "arn:aws:elasticloadbalancing:us-east-1:302780033379:targetgroup/tg-availability-dev/05ce59e0d1279519"

kms_dynamodb_arn  = "arn:aws:kms:us-east-1:302780033379:key/220ed17a-789b-4f6a-8537-cfefe3812092"
tickets_table_arn = "arn:aws:dynamodb:us-east-1:302780033379:table/table-ticketing-co-tickets-dev"

container_image = "302780033379.dkr.ecr.us-east-1.amazonaws.com/ecr-ticketing-co-ticket-availability-dev:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
