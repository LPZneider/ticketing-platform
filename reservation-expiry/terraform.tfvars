env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "us-east-1"

# Outputs de transversal_networking:
vpc_id    = "<transversal_networking.vpc_id>"
vpc_cidr  = "<transversal_networking.vpc_cidr>"
subnet_id = "<transversal_networking.private_subnet_ids[reservation-expiry]>"

# Outputs de transversal_ecs:
ecs_cluster_arn = "<transversal_ecs.ecs_cluster_arn>"

# Outputs de ticket-reservation:
sqs_expiry_arn = "<ticket-reservation.sqs_expiry_arn>"
sqs_expiry_url = "<ticket-reservation.sqs_expiry_url>"

# Outputs de transversal_sqs:
kms_sqs_arn = "<transversal_sqs.kms_sqs_arn>"

# Outputs de transversal_data:
kms_dynamodb_arn  = "<transversal_data.kms_dynamodb_arn>"
tickets_table_arn = "<transversal_data.tickets_table_arn>"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
