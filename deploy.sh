#!/usr/bin/env bash
# deploy.sh — despliega todos los componentes en orden e inyecta outputs entre ellos
# Requisitos: aws cli + terraform
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REGION="us-east-1"

deploy() {
  local dir="$1"
  echo ""
  echo "=========================================="
  echo " Desplegando: $dir"
  echo "=========================================="
  cd "$ROOT/$dir"
  terraform init -reconfigure
  terraform apply -var-file=terraform.tfvars -auto-approve
}

# Obtiene un output escalar de terraform (string, number)
get_output() {
  local dir="$1"
  local key="$2"
  terraform -chdir="$ROOT/$dir" output -raw "$key"
}

# Obtiene el ID de una subnet por nombre usando AWS CLI
# La subnet fue creada con Name = subnet-ticketing-co-<nombre>-dev
get_subnet() {
  local name="$1"
  aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=subnet-ticketing-co-${name}-dev" \
    --query "Subnets[0].SubnetId" \
    --output text
}

# ─── PASO 1: transversal_networking ─────────────────────────────────────────
deploy transversal_networking

VPC_ID=$(get_output transversal_networking vpc_id)
VPC_CIDR=$(get_output transversal_networking vpc_cidr)

# Las subnets se consultan por tag Name usando AWS CLI (sin jq)
SUBNET_RESERVATION=$(get_subnet "ticket-reservation")
SUBNET_PURCHASE=$(get_subnet "ticket-purchase")
SUBNET_EXPIRY=$(get_subnet "reservation-expiry")
SUBNET_AVAILABILITY=$(get_subnet "ticket-availability")

echo "VPC_ID=$VPC_ID"
echo "VPC_CIDR=$VPC_CIDR"
echo "SUBNET_RESERVATION=$SUBNET_RESERVATION"
echo "SUBNET_PURCHASE=$SUBNET_PURCHASE"
echo "SUBNET_EXPIRY=$SUBNET_EXPIRY"
echo "SUBNET_AVAILABILITY=$SUBNET_AVAILABILITY"

# ─── PASO 2: transversal_ecs + transversal_sqs + transversal_data ────────────
deploy transversal_ecs
deploy transversal_sqs
deploy transversal_data

ECS_CLUSTER_ARN=$(get_output transversal_ecs ecs_cluster_arn)
ECS_CLUSTER_NAME=$(get_output transversal_ecs ecs_cluster_name)
KMS_SQS_ARN=$(get_output transversal_sqs kms_sqs_arn)
KMS_DYNAMO_ARN=$(get_output transversal_data kms_dynamodb_arn)
TICKETS_TABLE_ARN=$(get_output transversal_data tickets_table_arn)
ORDERS_TABLE_ARN=$(get_output transversal_data orders_table_arn)

# ─── PASO 3: auth ────────────────────────────────────────────────────────────
cat > "$ROOT/auth/terraform.tfvars" <<EOF
env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "$REGION"

vpc_id             = "$VPC_ID"
vpc_cidr           = "$VPC_CIDR"
private_subnet_ids = ["$SUBNET_RESERVATION"]
lambda_zip_path    = "lambda_auth.zip"

tags = {
  project = "ticketing-platform"
}
EOF

deploy auth

LAMBDA_AUTH_ARN=$(get_output auth lambda_auth_arn)
LAMBDA_AUTH_INVOKE_ARN=$(get_output auth lambda_auth_invoke_arn)

# ─── PASO 4: transversal_api ─────────────────────────────────────────────────
cat > "$ROOT/transversal_api/terraform.tfvars" <<EOF
env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "$REGION"

vpc_id             = "$VPC_ID"
vpc_cidr           = "$VPC_CIDR"
private_subnet_ids = ["$SUBNET_RESERVATION", "$SUBNET_AVAILABILITY"]

lambda_authorizer_invoke_arn = "$LAMBDA_AUTH_INVOKE_ARN"
lambda_authorizer_arn        = "$LAMBDA_AUTH_ARN"

tags = {
  project = "ticketing-platform"
}
EOF

deploy transversal_api

SG_ALB_ID=$(get_output transversal_api sg_alb_id)
TG_RESERVATION_ARN=$(get_output transversal_api tg_reservation_arn)
TG_AVAILABILITY_ARN=$(get_output transversal_api tg_availability_arn)

# ─── PASO 5: ticket-reservation ──────────────────────────────────────────────
cat > "$ROOT/ticket-reservation/terraform.tfvars" <<EOF
env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "$REGION"

vpc_id    = "$VPC_ID"
vpc_cidr  = "$VPC_CIDR"
subnet_id = "$SUBNET_RESERVATION"
sg_alb_id = "$SG_ALB_ID"

ecs_cluster_arn    = "$ECS_CLUSTER_ARN"
ecs_cluster_name   = "$ECS_CLUSTER_NAME"
tg_reservation_arn = "$TG_RESERVATION_ARN"

kms_sqs_arn       = "$KMS_SQS_ARN"
kms_dynamodb_arn  = "$KMS_DYNAMO_ARN"
tickets_table_arn = "$TICKETS_TABLE_ARN"
orders_table_arn  = "$ORDERS_TABLE_ARN"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 512
memory          = 1024

tags = { project = "ticketing-platform" }
EOF

deploy ticket-reservation

SQS_PURCHASE_ARN=$(get_output ticket-reservation sqs_purchase_arn)
SQS_PURCHASE_URL=$(get_output ticket-reservation sqs_purchase_url)
SQS_EXPIRY_ARN=$(get_output ticket-reservation sqs_expiry_arn)
SQS_EXPIRY_URL=$(get_output ticket-reservation sqs_expiry_url)

# ─── PASO 6: ticket-purchase + reservation-expiry + ticket-availability ──────
cat > "$ROOT/ticket-purchase/terraform.tfvars" <<EOF
env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "$REGION"

vpc_id    = "$VPC_ID"
vpc_cidr  = "$VPC_CIDR"
subnet_id = "$SUBNET_PURCHASE"

ecs_cluster_arn  = "$ECS_CLUSTER_ARN"
sqs_purchase_arn = "$SQS_PURCHASE_ARN"
sqs_purchase_url = "$SQS_PURCHASE_URL"

kms_sqs_arn       = "$KMS_SQS_ARN"
kms_dynamodb_arn  = "$KMS_DYNAMO_ARN"
tickets_table_arn = "$TICKETS_TABLE_ARN"
orders_table_arn  = "$ORDERS_TABLE_ARN"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 512
memory          = 1024

tags = { project = "ticketing-platform" }
EOF

cat > "$ROOT/reservation-expiry/terraform.tfvars" <<EOF
env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "$REGION"

vpc_id    = "$VPC_ID"
vpc_cidr  = "$VPC_CIDR"
subnet_id = "$SUBNET_EXPIRY"

ecs_cluster_arn = "$ECS_CLUSTER_ARN"
sqs_expiry_arn  = "$SQS_EXPIRY_ARN"
sqs_expiry_url  = "$SQS_EXPIRY_URL"

kms_sqs_arn       = "$KMS_SQS_ARN"
kms_dynamodb_arn  = "$KMS_DYNAMO_ARN"
tickets_table_arn = "$TICKETS_TABLE_ARN"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
EOF

cat > "$ROOT/ticket-availability/terraform.tfvars" <<EOF
env        = "dev"
capacity   = "ticketing"
country    = "co"
aws_region = "$REGION"

vpc_id    = "$VPC_ID"
vpc_cidr  = "$VPC_CIDR"
subnet_id = "$SUBNET_AVAILABILITY"
sg_alb_id = "$SG_ALB_ID"

ecs_cluster_arn     = "$ECS_CLUSTER_ARN"
tg_availability_arn = "$TG_AVAILABILITY_ARN"

kms_dynamodb_arn  = "$KMS_DYNAMO_ARN"
tickets_table_arn = "$TICKETS_TABLE_ARN"

container_image = "nginx:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
EOF

deploy ticket-purchase
deploy reservation-expiry
deploy ticket-availability

echo ""
echo "=========================================="
echo " Despliegue completo"
echo "=========================================="
