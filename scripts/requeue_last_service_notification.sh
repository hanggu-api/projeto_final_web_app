#!/usr/bin/env bash
set -euo pipefail

# Re-dispara notificação de prestadores para um serviço.
# Uso:
#   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... ./scripts/requeue_last_service_notification.sh
#   SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... ./scripts/requeue_last_service_notification.sh --service-id 7e20fdc6-c82b-46c0-8d9c-40e18881df57
#
# Regras:
# - Se --service-id for informado, usa ele diretamente.
# - Caso contrário, busca o último serviço elegível (não terminal) em service_requests.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SERVICE_ID=""
DEFAULT_SERVICE_ID="7e20fdc6-c82b-46c0-8d9c-40e18881df57"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service-id)
      SERVICE_ID="${2:-}"
      shift 2
      ;;
    --help|-h)
      cat <<USAGE
Uso:
  SUPABASE_URL=... SUPABASE_SERVICE_ROLE_KEY=... ./scripts/requeue_last_service_notification.sh [--service-id <uuid>]
USAGE
      exit 0
      ;;
    *)
      echo "Argumento inválido: $1" >&2
      exit 1
      ;;
  esac
done

SUPABASE_URL="${SUPABASE_URL:-}"
SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-${SERVICE_ROLE_KEY:-}}"

if [[ -z "$SUPABASE_URL" || -z "$SUPABASE_SERVICE_ROLE_KEY" ]]; then
  echo "❌ Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY (ou SERVICE_ROLE_KEY)." >&2
  exit 1
fi

if [[ -z "$SERVICE_ID" ]]; then
  SERVICE_ID="$DEFAULT_SERVICE_ID"
fi

# Se não foi informado explicitamente e o default não existir/for terminal, tenta último elegível.
if [[ "$SERVICE_ID" == "$DEFAULT_SERVICE_ID" ]]; then
  latest_json="$(curl -sS "${SUPABASE_URL}/rest/v1/service_requests?select=id,status,created_at&status=not.in.(completed,cancelled,canceled,expired,refunded,closed)&order=created_at.desc&limit=1" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json")"

  latest_id="$(printf '%s' "$latest_json" | jq -r '.[0].id // empty')"
  latest_status="$(printf '%s' "$latest_json" | jq -r '.[0].status // empty')"

  if [[ -n "$latest_id" ]]; then
    SERVICE_ID="$latest_id"
    echo "ℹ️ Último serviço elegível encontrado: $SERVICE_ID (status=$latest_status)"
  else
    echo "ℹ️ Nenhum serviço elegível encontrado; usando service_id padrão informado: $SERVICE_ID"
  fi
fi

echo "🚀 Disparando redisparo de notificação para service_id=$SERVICE_ID"

dispatch_response="$(curl -sS "${SUPABASE_URL}/functions/v1/dispatch" \
  -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"serviceId\":\"${SERVICE_ID}\",\"action\":\"start_dispatch\"}")"

echo "📦 Resposta dispatch:"
printf '%s\n' "$dispatch_response" | jq .

queued="$(printf '%s' "$dispatch_response" | jq -r '.queued // empty')"
if [[ -n "$queued" ]]; then
  echo "✅ Redisparo concluído. queued=$queued"
else
  echo "⚠️ Dispatch respondeu sem campo 'queued'. Verifique payload acima."
fi
