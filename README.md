# ticketing-platform — IaC Terraform

Arquitectura reactiva de ticketing sobre AWS con recursos nativos `hashicorp/aws`.

## Estructura

```
ticketing-platform/
├── transversal_networking/   # VPC, subnets privadas, VPC endpoints (DynamoDB, SQS, ECR, Secrets Manager)
├── transversal_ecs/          # ECS Cluster Fargate compartido + KMS logs
├── transversal_sqs/          # KMS compartido para todas las SQS
├── transversal_data/         # DynamoDB (tickets + orders) + KMS
├── transversal_api/          # ALB interno + API Gateway + VPC Link + WAF
├── auth/                     # Lambda authorizer + Secrets Manager + IAM
├── ticket-reservation/       # ECS service + SQS "P" + SQS "R" (delay 600s) + IAM
├── ticket-purchase/          # ECS service (SQS consumer) + DLQ + IAM
├── reservation-expiry/       # ECS service (SQS consumer) + IAM
└── ticket-availability/      # ECS service (read-only DynamoDB) + IAM
```

## Orden de despliegue

1. `transversal_networking`
2. `transversal_ecs` + `transversal_sqs` + `transversal_data` (paralelo)
3. `auth`
4. `transversal_api`
5. `ticket-reservation`
6. `ticket-purchase` + `reservation-expiry` + `ticket-availability` (paralelo)

## Despliegue por componente

```bash
cd <componente>
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

## Supuestos y simplificaciones

- Un único ECS Cluster Fargate compartido para los 4 servicios
- `container_image = "nginx:latest"` como placeholder; reemplazar con imagen real
- Sin autoscaling configurado (agregar `aws_appautoscaling_target` + políticas por servicio)
- ALB en HTTP (puerto 80); en producción agregar certificado ACM y listener HTTPS 443
- Remote state no configurado; agregar `backend "s3"` en cada componente para producción
- Lambda authorizer requiere un ZIP real en `lambda_zip_path`; el placeholder es `lambda_auth.zip`
- Los `terraform.tfvars` usan placeholders (`vpc-xxxxxxxxx`, `ACCOUNT_ID`) que deben reemplazarse con los outputs reales del componente anterior
