#!/usr/bin/env bash
# destroy.sh — destruye toda la infraestructura en orden inverso al deploy
# Requisitos: aws cli + terraform en PATH, credenciales AWS configuradas
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

destroy() {
  local dir="$1"
  echo ""
  echo "=========================================="
  echo " Destruyendo: $dir"
  echo "=========================================="
  cd "$ROOT/$dir"
  if [ ! -f terraform.tfstate ] || [ "$(python3 -c "import json,sys; d=json.load(open('terraform.tfstate')); print(len(d.get('resources',[])))")" = "0" ]; then
    echo " -> Sin estado, omitiendo."
    return
  fi
  terraform init -reconfigure
  terraform destroy -var-file=terraform.tfvars -auto-approve
}

echo ""
echo "=========================================="
echo " DESTROY — Ticketing Platform"
echo " Se destruirán TODOS los recursos de AWS"
echo "=========================================="
echo ""
read -p "¿Confirmas? Escribe 'destroy' para continuar: " CONFIRM
if [ "$CONFIRM" != "destroy" ]; then
  echo "Cancelado."
  exit 0
fi

# ─── PASO 6 (inverso): servicios ECS + SQS ────────────────────────────────
destroy ticket-availability
destroy reservation-expiry
destroy ticket-purchase

# ─── PASO 5 (inverso): ticket-reservation (tiene las colas SQS) ───────────
destroy ticket-reservation

# ─── PASO 4 (inverso): transversal_api (NLB, API GW, WAF, VPC Link) ───────
destroy transversal_api

# ─── PASO 3 (inverso): auth (Lambda + Secrets Manager) ────────────────────
destroy auth

# ─── PASO 2 (inverso): data + sqs + ecs ───────────────────────────────────
destroy transversal_data
destroy transversal_sqs
destroy transversal_ecs

# ─── PASO 1 (inverso): networking — VPC y endpoints (debe ser el último) ──
destroy transversal_networking

echo ""
echo "=========================================="
echo " Infraestructura destruida"
echo " Nota: las KMS keys tienen ventana de"
echo " eliminación de 7 días (mínimo AWS)."
echo "=========================================="
