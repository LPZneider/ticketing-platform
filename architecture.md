# Arquitectura — Ticketing Platform (dev, us-east-1)

## Flujo de entrada

```
  INTERNET
     │
     ▼
┌─────────────────────────────────────────────────────┐
│              API GATEWAY REST (REGIONAL)             │
│              api-ticketing-co-dev                    │
│                                                      │
│  WAF WebACL ──► CommonRuleSet + KnownBadInputs       │
│                                                      │
│  Lambda REQUEST Authorizer (TTL 300 s)               │
│    └──► lambda-auth-ticketing-co-dev                 │
│              └──► Secrets Manager                    │
│                   secret-ticketing-co-auth-dev       │
│                                                      │
│  Rutas expuestas:                                    │
│  POST /events          ──► :8080 (reservation)       │
│  POST /purchases       ──► :8080 (reservation)       │
│  GET  /events          ──► :8081 (availability)      │
│  GET  /events/{id}/availability ──► :8081            │
│  GET  /orders/{id}     ──► :8081 (availability)      │
└─────────────────────────────┬───────────────────────┘
                              │  VPC Link
                              ▼
              ┌───────────────────────────┐
              │    NLB — nlb-ticketing    │
              │   us-east-1a + us-east-1b │
              │                           │
              │  Listener :8080 ──────────┼──► ticket-reservation
              │  Listener :8081 ──────────┼──► ticket-availability
              └───────────────────────────┘
```

> **¿Por qué NLB y no ALB?**
> La REST API Gateway solo permite VPC Links hacia Network Load Balancers.
> El routing por método HTTP (POST vs GET) lo hace el API Gateway antes de llegar al NLB;
> el NLB solo diferencia servicios por puerto TCP.

---

## Servicios ECS Fargate

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ECS Cluster: ecs-ticketing-co-dev                                           │
│                                                                               │
│  ┌─────────────────────┐     ┌──────────────────────────┐                   │
│  │  ticket-reservation  │     │  ticket-availability     │                   │
│  │  subnet 10.0.1.0/24 │     │  subnet 10.0.4.0/24      │                   │
│  │  NLB port :8080     │     │  NLB port :8081          │                   │
│  │                     │     │                          │                   │
│  │  POST /events       │     │  GET  /events            │                   │
│  │  POST /purchases    │     │  GET  /events/{id}/avail │                   │
│  └──────────┬──────────┘     │  GET  /orders/{id}       │                   │
│             │                └──────────────────────────┘                   │
│             │ Publica                                                         │
│             ▼                                                                 │
│  ┌──────────────────────────────────────────────────┐                        │
│  │  SQS: sqs-purchase-requests                      │                        │
│  │  SQS: sqs-reservation-expiry  (delay: 600 s)     │                        │
│  └──────────┬───────────────────┬───────────────────┘                        │
│             │                   │  Consume                                    │
│             ▼                   ▼                                             │
│  ┌────────────────────┐  ┌───────────────────────┐                           │
│  │  ticket-purchase   │  │  reservation-expiry   │                           │
│  │  subnet 10.0.2/24  │  │  subnet 10.0.3.0/24   │                           │
│  │  (SQS consumer)    │  │  (SQS consumer)       │                           │
│  │  DLQ: 3 reintentos │  └───────────────────────┘                           │
│  │  14 días retención │                                                       │
│  └────────────────────┘                                                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Capa de datos

```
┌──────────────────────────────────────┐   ┌─────────────────────────────┐
│  DynamoDB: tickets                   │   │  DynamoDB: orders           │
│  PK: ticketId  ·  SK: eventType      │   │  PK: orderId  ·  SK: timestamp│
│  GSI: idx_status (status + ticketId) │   │                             │
│  TTL: expiration_time                │   │                             │
└────────────────────┬─────────────────┘   └──────────────┬──────────────┘
                     │                                     │
   Escribe ──────────┤◄─── ticket-reservation              │
   Lee (GSI) ────────┤◄─── ticket-availability             │◄─── ticket-availability (lee)
   Escribe ──────────┤◄─── reservation-expiry              │◄─── ticket-purchase (escribe)
   Lee ─────────────┘◄─── ticket-purchase (verifica)      │
```

| Servicio             | tabla `tickets`          | tabla `orders`         |
|----------------------|--------------------------|------------------------|
| ticket-reservation   | ✏️ Escribe               | —                      |
| ticket-availability  | 📖 Lee (GSI idx_status)  | 📖 Lee (por orderId)   |
| ticket-purchase      | 📖 Lee (verifica ticket) | ✏️ Escribe             |
| reservation-expiry   | ✏️ Escribe (expira)      | —                      |

---

## Red (VPC privada, sin NAT Gateway)

```
VPC: 10.0.0.0/16 (us-east-1)

  Subnets privadas (us-east-1a):
    10.0.1.0/24  ── ticket-reservation
    10.0.2.0/24  ── ticket-purchase
    10.0.3.0/24  ── reservation-expiry
    10.0.4.0/24  ── ticket-availability

  Subnet NLB secundaria (us-east-1b):
    10.0.10.0/24 ── alb-b  (solo para cumplir el requisito de 2 AZs del NLB)

  VPC Endpoints (sin NAT):
    Gateway  ── DynamoDB
    Interface── SQS            ─┐
    Interface── Secrets Manager  ├─ todos en subnet ticket-reservation (us-east-1a)
    Interface── ECR API          │
    Interface── ECR DKR         ─┘
```

---

## IAM por servicio

| Servicio            | Execution Role                   | Task Role (permisos de app)                  |
|---------------------|----------------------------------|----------------------------------------------|
| ticket-reservation  | ECR pull + CW Logs               | SQS:Send, DynamoDB:PutItem/UpdateItem, KMS   |
| ticket-availability | ECR pull + CW Logs               | DynamoDB:GetItem/Query (idx_status), KMS     |
| ticket-purchase     | ECR pull + CW Logs               | SQS:Receive/Delete, DynamoDB:Write, KMS      |
| reservation-expiry  | ECR pull + CW Logs               | SQS:Receive/Delete, DynamoDB:UpdateItem, KMS |
| lambda-auth         | CW Logs + VPC                    | SecretsManager:GetSecretValue, KMS           |
