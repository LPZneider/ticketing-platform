#!/usr/bin/env bash
# deploy.sh — despliega todos los componentes en orden e inyecta outputs entre ellos
# Requisitos: aws cli + terraform + docker + gradle en PATH, credenciales AWS configuradas
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MS_ROOT="$(dirname "$ROOT")"   # directorio padre donde viven los repos de MS
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
get_subnet() {
  local name="$1"
  aws ec2 describe-subnets \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=subnet-ticketing-co-${name}-dev" \
    --query "Subnets[0].SubnetId" \
    --output text
}

# Login a ECR (se ejecuta una sola vez al inicio del pipeline)
ecr_login() {
  local account
  account=$(aws sts get-caller-identity --query Account --output text)
  local registry="${account}.dkr.ecr.${REGION}.amazonaws.com"
  echo "--- ECR login: $registry ---"
  aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "$registry"
}

# Compila el JAR con Gradle, construye la imagen Docker y la sube a ECR
# $1 = nombre del repo del MS  (e.g. "ticket-reservation-service")
# $2 = URL del repositorio ECR (e.g. "302780033379.dkr.ecr.us-east-1.amazonaws.com/ecr-...")
# $3 = tag de imagen           (default: "latest")
build_push() {
  local svc_repo="$1"
  local ecr_url="$2"
  local tag="${3:-latest}"
  local svc_dir="$MS_ROOT/$svc_repo"

  echo ""
  echo "--- Build Gradle: $svc_repo ---"
  cd "$svc_dir"
  ./gradlew :applications:app-service:bootJar

  # Copiar el JAR al contexto del Dockerfile
  local jar
  jar=$(find "$svc_dir/applications/app-service/build/libs" -name "*.jar" | head -1)
  cp "$jar" "$svc_dir/deployment/"

  echo "--- Docker build & push: $ecr_url:$tag ---"
  docker build -t "$ecr_url:$tag" "$svc_dir/deployment"
  docker push "$ecr_url:$tag"
  echo "✓ Imagen publicada: $ecr_url:$tag"

  cd "$ROOT"
}

# Fuerza un nuevo deployment en ECS para que tome la imagen actualizada
force_redeploy() {
  local svc_module="$1"   # módulo terraform del servicio
  local svc_name
  svc_name=$(get_output "$svc_module" ecs_service_name)
  aws ecs update-service \
    --cluster "$ECS_CLUSTER_NAME" \
    --service "$svc_name" \
    --force-new-deployment \
    --region "$REGION" > /dev/null
  echo "✓ ECS redeploy disparado: $svc_name"
}

# ─── PASO 1: transversal_networking ─────────────────────────────────────────
deploy transversal_networking

VPC_ID=$(get_output transversal_networking vpc_id)
VPC_CIDR=$(get_output transversal_networking vpc_cidr)
SUBNET_ALB_B=$(get_output transversal_networking alb_secondary_subnet_id)

SUBNET_RESERVATION=$(get_subnet "ticket-reservation")
SUBNET_PURCHASE=$(get_subnet "ticket-purchase")
SUBNET_EXPIRY=$(get_subnet "reservation-expiry")
SUBNET_AVAILABILITY=$(get_subnet "ticket-availability")

echo "VPC_ID=$VPC_ID"
echo "VPC_CIDR=$VPC_CIDR"
echo "SUBNET_ALB_B=$SUBNET_ALB_B"
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
lambda_source_dir  = "${ROOT}/../lambda-auth/src"

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
private_subnet_ids = ["$SUBNET_RESERVATION", "$SUBNET_ALB_B"]

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

# ─── ECR login — una sola vez antes de los servicios ─────────────────────────
ecr_login

# ─── PASO 5: ticket-reservation ──────────────────────────────────────────────
# 5a. Primera apply: crea ECR repo + ECS con placeholder
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
ECR_RESERVATION_URL=$(get_output ticket-reservation ecr_repository_url)

# 5b. Build + push imagen real
build_push "ticket-reservation-service" "$ECR_RESERVATION_URL"

# 5c. Segunda apply: actualiza task definition con la imagen real
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

container_image = "$ECR_RESERVATION_URL:latest"
desired_count   = 1
cpu             = 512
memory          = 1024

tags = { project = "ticketing-platform" }
EOF

deploy ticket-reservation
force_redeploy ticket-reservation

# ─── PASO 6: ticket-purchase + reservation-expiry + ticket-availability ──────

# ── ticket-purchase ──
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

deploy ticket-purchase
ECR_PURCHASE_URL=$(get_output ticket-purchase ecr_repository_url)
build_push "ticket-purchase-service" "$ECR_PURCHASE_URL"

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

container_image = "$ECR_PURCHASE_URL:latest"
desired_count   = 1
cpu             = 512
memory          = 1024

tags = { project = "ticketing-platform" }
EOF

deploy ticket-purchase
force_redeploy ticket-purchase

# ── reservation-expiry ──
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

deploy reservation-expiry
ECR_EXPIRY_URL=$(get_output reservation-expiry ecr_repository_url)
build_push "reservation-expiry-service" "$ECR_EXPIRY_URL"

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

container_image = "$ECR_EXPIRY_URL:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
EOF

deploy reservation-expiry
force_redeploy reservation-expiry

# ── ticket-availability ──
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

deploy ticket-availability
ECR_AVAILABILITY_URL=$(get_output ticket-availability ecr_repository_url)
build_push "ticket-availability-service" "$ECR_AVAILABILITY_URL"

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

container_image = "$ECR_AVAILABILITY_URL:latest"
desired_count   = 1
cpu             = 256
memory          = 512

tags = { project = "ticketing-platform" }
EOF

deploy ticket-availability
force_redeploy ticket-availability

echo ""
echo "=========================================="
echo " Despliegue completo"
echo "=========================================="
