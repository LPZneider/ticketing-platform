# Ticketing Platform — IaC Terraform

Plataforma de venta de tickets para eventos construida sobre AWS con arquitectura de microservicios reactivos. Cada servicio es independiente, se despliega en ECS Fargate y se comunica de forma asíncrona a través de SQS. La infraestructura completa está definida como código con Terraform.

---

## Descripción de la solución

El sistema permite crear eventos, reservar tickets, procesar pagos y liberar tickets no confirmados de forma automática. Está compuesto por 4 microservicios Java (Spring WebFlux) y una Lambda de autorización:

| Servicio | Responsabilidad |
|---|---|
| `ticket-reservation` | Crea eventos y reserva tickets. Publica en SQS para purchase y expiry |
| `ticket-purchase` | Consume SQS, confirma el pago y marca la orden como `CONFIRMED` |
| `reservation-expiry` | Consume SQS con delay de 3 min. Si la orden sigue pendiente, elimina los tickets reservados y libera el cupo |
| `ticket-availability` | Consultas de solo lectura: disponibilidad de eventos y estado de órdenes |
| `lambda-auth` | Authorizer de API Gateway. Decodifica el JWT y extrae `userId` y `userRole` |

### Flujo principal

```
Cliente
  │
  ▼
API Gateway (WAF + Lambda Authorizer JWT)
  │
  ├── POST /api/v1/events      ──► ticket-reservation  (crea evento)
  ├── POST /api/v1/purchases   ──► ticket-reservation  (reserva tickets)
  ├── GET  /api/v1/events/{id}/availability ──► ticket-availability
  └── GET  /api/v1/orders/{id}/status       ──► ticket-availability

ticket-reservation
  ├── DynamoDB: crea orden PENDING_CONFIRMATION + tickets RESERVED
  ├── SQS purchase-requests ──► ticket-purchase (confirma pago → CONFIRMED + SOLD)
  └── SQS reservation-expiry (delay 3 min) ──► reservation-expiry
          └── Si orden sigue PENDING_CONFIRMATION → elimina tickets RESERVED + restaura cupo
```

---

## Estructura del repositorio

```
ticketing-platform/
├── transversal_networking/   # VPC, subnets privadas, VPC Endpoints (sin NAT Gateway)
├── transversal_ecs/          # ECS Cluster Fargate compartido + KMS logs
├── transversal_sqs/          # KMS compartido para todas las colas SQS
├── transversal_data/         # DynamoDB (tickets + orders) + KMS
├── transversal_api/          # NLB + API Gateway REST + VPC Link + WAF
├── auth/                     # Lambda authorizer + Secrets Manager + IAM
├── ticket-reservation/       # ECS service + SQS purchase-requests + SQS reservation-expiry + IAM
├── ticket-purchase/          # ECS service (consumer SQS) + DLQ + IAM
├── reservation-expiry/       # ECS service (consumer SQS) + IAM
├── ticket-availability/      # ECS service (read-only DynamoDB) + IAM
├── deploy.sh                 # Despliegue completo end-to-end
├── update-service.sh         # Rebuild + redeploy de un servicio individual
└── destroy.sh                # Destrucción de toda la infraestructura
```

---

## Requisitos previos

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) >= 2.x configurado con credenciales válidas
- [Docker](https://docs.docker.com/get-docker/) con soporte `linux/amd64`
- [Java](https://adoptium.net/) 25 (Temurin) y Gradle (wrapper incluido en cada MS)
- Permisos IAM suficientes para crear recursos ECS, ECR, DynamoDB, SQS, API Gateway, Lambda, IAM roles y VPC

### Configurar credenciales AWS

```bash
export AWS_SHARED_CREDENTIALS_FILE=~/.aws/credentials
export AWS_CONFIG_FILE=~/.aws/config
```

O directamente:

```bash
aws configure
# AWS Access Key ID: <access_key>
# AWS Secret Access Key: <secret_key>
# Default region name: us-east-1
# Default output format: json
```

---

## Instalación y despliegue

### Opción A — Despliegue completo automatizado

Ejecuta todos los módulos Terraform en orden, construye las imágenes Docker y las sube a ECR:

```bash
cd ticketing-platform
bash deploy.sh
```

El script:
1. Despliega la infraestructura transversal (red, ECS cluster, SQS, DynamoDB)
2. Despliega auth y API Gateway
3. Por cada microservicio: crea el ECR, hace `gradle bootJar`, construye la imagen Docker, la sube a ECR y fuerza el redeploy en ECS

### Opción B — Despliegue por componente

```bash
cd ticketing-platform/<componente>
terraform init
terraform plan  -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Orden obligatorio:

```
1. transversal_networking
2. transversal_ecs  +  transversal_sqs  +  transversal_data   (paralelo)
3. auth
4. transversal_api
5. ticket-reservation
6. ticket-purchase  +  reservation-expiry  +  ticket-availability   (paralelo)
```

### Actualizar un servicio individual

Cuando solo cambia el código de un microservicio:

```bash
cd ticketing-platform
bash update-service.sh ticket-reservation
# Opciones: ticket-reservation | ticket-purchase | reservation-expiry | ticket-availability
```

El script hace rebuild del JAR, construye la imagen Docker, la sube a ECR y fuerza un nuevo deployment en ECS.

### Destruir la infraestructura

```bash
cd ticketing-platform
bash destroy.sh
```

---

## Levantar los servicios con Docker (local)

Cada microservicio tiene un `Dockerfile` multi-stage en `<repo>/deployment/Dockerfile`. Para correr un servicio localmente:

```bash
# 1. Compilar el JAR
cd ticket-reservation-service
./gradlew :app-service:bootJar

# 2. Construir la imagen
docker build \
  -f deployment/Dockerfile \
  -t ticket-reservation:local \
  .

# 3. Correr el contenedor
docker run -p 8080:8080 \
  -e AWS_REGION=us-east-1 \
  -e AWS_ACCESS_KEY_ID=<access_key> \
  -e AWS_SECRET_ACCESS_KEY=<secret_key> \
  -e SQS_PURCHASE_URL=<url_sqs_purchase> \
  -e SQS_EXPIRY_URL=<url_sqs_expiry> \
  ticket-reservation:local
```

> Los servicios no tienen base de datos local — dependen de DynamoDB y SQS en AWS. Para desarrollo local se recomienda usar [LocalStack](https://localstack.cloud/) o apuntar a los recursos reales del entorno `dev`.

---

## Decisiones arquitectónicas

### Sin NAT Gateway
Todos los servicios viven en subnets privadas sin acceso a internet. La comunicación con DynamoDB, SQS, ECR y Secrets Manager se hace a través de **VPC Endpoints**, eliminando el costo del NAT Gateway y reduciendo la superficie de ataque.

### NLB en lugar de ALB
API Gateway REST solo soporta VPC Links hacia **Network Load Balancers**. El routing por método HTTP (POST vs GET) lo resuelve el API Gateway antes de llegar al NLB; el NLB diferencia servicios únicamente por puerto TCP (`:8080` reservation, `:8081` availability).

### Comunicación asíncrona con SQS
La reserva de tickets y la confirmación de pago son operaciones desacopladas. Si `ticket-purchase` está caído, los mensajes persisten en SQS (retención 14 días, DLQ con 3 reintentos). El delay de 3 minutos en la cola de expiry garantiza que `ticket-purchase` tenga tiempo de procesar antes de que expiry actúe.

### Single-table DynamoDB para tickets
La tabla `tickets` usa `pk=eventId` y `sk=ticketId`, con un ítem especial `sk=METADATA` que almacena el `availableCount` del evento. Esto permite actualizar el cupo disponible en la misma transacción que se crean los tickets, garantizando consistencia sin transacciones distribuidas.

### Tickets RESERVED se eliminan al expirar
En lugar de volver los tickets a estado `AVAILABLE`, el servicio `reservation-expiry` los **elimina** de DynamoDB. Esto mantiene la tabla limpia — solo existen ítems `SOLD` y `METADATA` — y evita estados intermedios que puedan causar inconsistencias.

### JWT sin verificación de firma
El Lambda authorizer decodifica el payload del JWT sin verificar la firma (simplificación para la prueba técnica). En producción se debe verificar con la clave pública almacenada en Secrets Manager.

### Estado de Terraform local
Cada módulo guarda su `terraform.tfstate` localmente. Para producción se debe configurar un backend remoto en S3 con bloqueo en DynamoDB.

---

## Ejemplos de uso de los endpoints

La URL base es el endpoint del API Gateway desplegado. Todos los endpoints requieren el header `Authorization: Bearer <token>`.

**Token de prueba (admin):**
```
eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAidXNlci1hZG1pbi0wMDEiLCAicm9sZSI6ICJhZG1pbiIsICJ1c2VySWQiOiAidXNlci1hZG1pbi0wMDEiLCAidXNlclJvbGUiOiAiYWRtaW4ifQ.fakesig
```

**Token de prueba (usuario):**
```
eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAidXNlci0xMjM0NTYiLCAicm9sZSI6ICJ1c2VyIiwgInVzZXJJZCI6ICJ1c2VyLTEyMzQ1NiIsICJ1c2VyUm9sZSI6ICJ1c2VyIn0.fakesig
```

---

### 1. Crear un evento

```bash
POST /api/v1/events
```

```bash
curl -X POST https://<api-gateway-url>/api/v1/events \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token_admin>" \
  -H "message-id: msg-001" \
  -H "region: us-east-1" \
  -d '{
    "name": "Concierto BTS Bogotá",
    "date": "2025-12-15T20:00:00Z",
    "venue": "El Campin",
    "totalCapacity": 20000
  }'
```

Respuesta exitosa (`200`):
```json
{
  "status": "SUCCESS",
  "message": "Event created successfully",
  "data": {
    "eventId": "abeb2916-5ad2-431c-a35d-65e8886296a7",
    "name": "Concierto BTS Bogotá",
    "venue": "El Campin",
    "totalCapacity": 20000,
    "availableCount": 20000
  }
}
```

---

### 2. Reservar tickets

```bash
POST /api/v1/purchases
```

```bash
curl -X POST https://<api-gateway-url>/api/v1/purchases \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token_usuario>" \
  -H "message-id: msg-002" \
  -H "region: us-east-1" \
  -d '{
    "eventId": "abeb2916-5ad2-431c-a35d-65e8886296a7",
    "quantity": 2,
    "userId": "user-123456"
  }'
```

Respuesta exitosa (`200`):
```json
{
  "status": "SUCCESS",
  "message": "Tickets reserved successfully",
  "data": {
    "orderId": "order-uuid-generado",
    "status": "PENDING_CONFIRMATION",
    "tickets": ["ticket-uuid-1", "ticket-uuid-2"]
  }
}
```

> La orden queda en `PENDING_CONFIRMATION`. El servicio `ticket-purchase` la procesará de forma asíncrona y la pasará a `CONFIRMED`. Si no se confirma en 3 minutos, `reservation-expiry` la marcará como `EXPIRED` y liberará los tickets.

---

### 3. Consultar disponibilidad de un evento

```bash
GET /api/v1/events/{eventId}/availability
```

```bash
curl https://<api-gateway-url>/api/v1/events/abeb2916-5ad2-431c-a35d-65e8886296a7/availability \
  -H "Authorization: Bearer <token_usuario>" \
  -H "message-id: msg-003" \
  -H "region: us-east-1"
```

Respuesta exitosa (`200`):
```json
{
  "status": "SUCCESS",
  "data": {
    "eventId": "abeb2916-5ad2-431c-a35d-65e8886296a7",
    "name": "Concierto BTS Bogotá",
    "availableCount": 19998
  }
}
```

---

### 4. Consultar estado de una orden

```bash
GET /api/v1/orders/{orderId}/status
```

```bash
curl https://<api-gateway-url>/api/v1/orders/order-uuid-generado/status \
  -H "Authorization: Bearer <token_usuario>" \
  -H "message-id: msg-004" \
  -H "region: us-east-1"
```

Respuesta exitosa (`200`):
```json
{
  "status": "SUCCESS",
  "data": {
    "orderId": "order-uuid-generado",
    "status": "CONFIRMED",
    "userId": "user-123456",
    "tickets": ["ticket-uuid-1", "ticket-uuid-2"]
  }
}
```

Estados posibles de una orden: `PENDING_CONFIRMATION` → `CONFIRMED` | `EXPIRED` | `REJECTED`
