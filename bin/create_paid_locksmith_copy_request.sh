#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "Erro: curl não encontrado." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Erro: jq não encontrado." >&2
  exit 1
fi

: "${SUPABASE_URL:?Defina SUPABASE_URL}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Defina SUPABASE_SERVICE_ROLE_KEY}"

LOCKSMITH_PROFESSION_NAME="${LOCKSMITH_PROFESSION_NAME:-Chaveiro}"
TASK_NAME="${TASK_NAME:-Cópia de Chave Simples}"
SERVICE_DESCRIPTION="${SERVICE_DESCRIPTION:-Pedido teste: cópia de chave simples próximo ao Mix Mateus da Babaçulândia}"
ADDRESS="${ADDRESS:-Mix Mateus - Babaçulândia, Imperatriz - MA (próximo ao Matheus)}"
LATITUDE="${LATITUDE:--5.5017472}"
LONGITUDE="${LONGITUDE:--47.45835915}"
CLIENT_EMAIL="${CLIENT_EMAIL:-passageiro2@gmail.com}"
PROVIDER_EMAILS_CSV="${PROVIDER_EMAILS_CSV:-chaveiro10@gmail.com,chaveiro12@gmail.com}"
PRICE_ESTIMATED_OVERRIDE="${PRICE_ESTIMATED_OVERRIDE:-}"
CALL_DISPATCH="${CALL_DISPATCH:-1}"

api_get() {
  local path="$1"
  curl -sS "${SUPABASE_URL}${path}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}"
}

api_post() {
  local path="$1"
  local body="$2"
  curl -sS -X POST "${SUPABASE_URL}${path}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    --data "${body}"
}

api_patch() {
  local path="$1"
  local body="$2"
  curl -sS -X PATCH "${SUPABASE_URL}${path}" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: return=representation" \
    --data "${body}"
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

first_item() {
  jq 'if type == "array" then .[0] else . end'
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

resolve_profession() {
  local encoded_name
  encoded_name="$(urlencode "${LOCKSMITH_PROFESSION_NAME}")"
  local result
  result="$(api_get "/rest/v1/professions?name=eq.${encoded_name}&select=id,name,category_id&limit=1" | first_item)"
  if [[ "$(jq -r '.id // empty' <<<"${result}")" == "" ]]; then
    result="$(api_get "/rest/v1/professions?name=ilike.*$(urlencode "${LOCKSMITH_PROFESSION_NAME}")*&select=id,name,category_id&limit=1" | first_item)"
  fi
  jq -e '.id != null' <<<"${result}" >/dev/null || {
    echo "Erro: profissão '${LOCKSMITH_PROFESSION_NAME}' não encontrada." >&2
    exit 1
  }
  echo "${result}"
}

resolve_task() {
  local profession_id="$1"
  local result
  result="$(api_get "/rest/v1/task_catalog?profession_id=eq.${profession_id}&name=eq.$(urlencode "${TASK_NAME}")&select=id,name,unit_price,profession_id&limit=1" | first_item)"
  jq -e '.id != null' <<<"${result}" >/dev/null || {
    echo "Erro: tarefa '${TASK_NAME}' não encontrada para a profissão ${profession_id}." >&2
    exit 1
  }
  echo "${result}"
}

resolve_client() {
  local result
  if [[ -n "${CLIENT_EMAIL}" ]]; then
    result="$(api_get "/rest/v1/users?email=eq.$(urlencode "${CLIENT_EMAIL}")&supabase_uid=not.is.null&select=id,email,supabase_uid,role&limit=1" | first_item)"
  else
    result="$(api_get "/rest/v1/users?role=eq.client&supabase_uid=not.is.null&select=id,email,supabase_uid,role&order=id.asc&limit=1" | first_item)"
  fi
  jq -e '.id != null and .supabase_uid != null' <<<"${result}" >/dev/null || {
    echo "Erro: cliente válido não encontrado." >&2
    exit 1
  }
  echo "${result}"
}

resolve_provider() {
  local email="$1"
  local result
  result="$(api_get "/rest/v1/users?email=eq.$(urlencode "${email}")&role=eq.provider&select=id,email,supabase_uid,role&limit=1" | first_item)"
  jq -e '.id != null and .supabase_uid != null' <<<"${result}" >/dev/null || {
    echo "Erro: prestador '${email}' não encontrado ou sem supabase_uid." >&2
    exit 1
  }
  echo "${result}"
}

assert_provider_profession() {
  local provider_user_id="$1"
  local profession_id="$2"
  local rows
  rows="$(api_get "/rest/v1/provider_professions?provider_user_id=eq.${provider_user_id}&profession_id=eq.${profession_id}&select=provider_user_id&limit=1")"
  jq -e 'length > 0' <<<"${rows}" >/dev/null || {
    echo "Erro: provider_user_id=${provider_user_id} não possui profession_id=${profession_id}." >&2
    exit 1
  }
}

mark_provider_online() {
  local provider_json="$1"
  local provider_id provider_uid email current_now patch_body upsert_body
  provider_id="$(jq -r '.id' <<<"${provider_json}")"
  provider_uid="$(jq -r '.supabase_uid' <<<"${provider_json}")"
  email="$(jq -r '.email' <<<"${provider_json}")"
  current_now="$(now_iso)"
  patch_body="$(jq -nc --arg ts "${current_now}" '{last_seen_at:$ts}')"
  api_patch "/rest/v1/users?id=eq.${provider_id}" "${patch_body}" >/dev/null
  upsert_body="$(jq -nc \
    --argjson provider_id "${provider_id}" \
    --arg provider_uid "${provider_uid}" \
    --argjson latitude "${LATITUDE}" \
    --argjson longitude "${LONGITUDE}" \
    --arg ts "${current_now}" \
    '[{provider_id:$provider_id,provider_uid:$provider_uid,latitude:$latitude,longitude:$longitude,updated_at:$ts}]')"
  curl -sS -X POST "${SUPABASE_URL}/rest/v1/provider_locations?on_conflict=provider_id" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    -H "Prefer: resolution=merge-duplicates,return=representation" \
    --data "${upsert_body}" >/dev/null
  echo "Prestador preparado online: ${email}"
}

create_service_request() {
  local client_json="$1"
  local profession_json="$2"
  local task_json="$3"
  local client_id client_uid profession_id profession_name category_id task_id unit_price price_estimated create_body
  client_id="$(jq -r '.id' <<<"${client_json}")"
  client_uid="$(jq -r '.supabase_uid' <<<"${client_json}")"
  profession_id="$(jq -r '.id' <<<"${profession_json}")"
  profession_name="$(jq -r '.name' <<<"${profession_json}")"
  category_id="$(jq -r '.category_id // 1' <<<"${profession_json}")"
  task_id="$(jq -r '.id' <<<"${task_json}")"
  unit_price="$(jq -r '.unit_price // 13.5' <<<"${task_json}")"
  price_estimated="${PRICE_ESTIMATED_OVERRIDE:-${unit_price}}"

  create_body="$(jq -nc \
    --argjson client_id "${client_id}" \
    --arg client_uid "${client_uid}" \
    --argjson category_id "${category_id}" \
    --arg description "${SERVICE_DESCRIPTION}" \
    --argjson latitude "${LATITUDE}" \
    --argjson longitude "${LONGITUDE}" \
    --arg address "${ADDRESS}" \
    --argjson price_estimated "${price_estimated}" \
    --arg profession "${profession_name}" \
    --argjson profession_id "${profession_id}" \
    --arg location_type "client" \
    --arg status "waiting_payment" \
    --arg payment_status "pending" \
    --argjson task_id "${task_id}" \
    '{
      client_id:$client_id,
      client_uid:$client_uid,
      category_id:$category_id,
      description:$description,
      latitude:$latitude,
      longitude:$longitude,
      address:$address,
      price_estimated:$price_estimated,
      price_upfront:0,
      status:$status,
      payment_status:$payment_status,
      profession:$profession,
      profession_id:$profession_id,
      location_type:$location_type,
      task_id:$task_id,
      fee_admin_rate:0,
      fee_admin_amount:0,
      amount_payable_on_site:$price_estimated
    }')"

  api_post "/rest/v1/service_requests_new" "${create_body}" | first_item
}

mark_service_paid_and_searching() {
  local service_id="$1"
  local patch_body
  patch_body="$(jq -nc \
    --arg status "searching" \
    --arg payment_status "paid_manual" \
    '{status:$status,payment_status:$payment_status}')"
  api_patch "/rest/v1/service_requests_new?id=eq.${service_id}" "${patch_body}" | first_item
}

call_dispatch() {
  local service_id="$1"
  local payload
  payload="$(jq -nc --arg serviceId "${service_id}" --arg action "start_dispatch" '{serviceId:$serviceId,action:$action}')"
  curl -sS -X POST "${SUPABASE_URL}/functions/v1/dispatch" \
    -H "apikey: ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY}" \
    -H "Content-Type: application/json" \
    --data "${payload}"
}

fetch_queue() {
  local service_id="$1"
  api_get "/rest/v1/notificacao_de_servicos?service_id=eq.${service_id}&select=id,service_id,provider_user_id,profession_id,status,ciclo_atual,queue_order,distance&order=queue_order.asc"
}

main() {
  local profession_json task_json client_json service_json service_id dispatch_json queue_json
  local profession_id provider_email provider_json

  profession_json="$(resolve_profession)"
  profession_id="$(jq -r '.id' <<<"${profession_json}")"
  task_json="$(resolve_task "${profession_id}")"
  client_json="$(resolve_client)"

  IFS=',' read -r -a provider_emails <<<"${PROVIDER_EMAILS_CSV}"
  for provider_email in "${provider_emails[@]}"; do
    provider_email="${provider_email// /}"
    [[ -n "${provider_email}" ]] || continue
    provider_json="$(resolve_provider "${provider_email}")"
    assert_provider_profession "$(jq -r '.id' <<<"${provider_json}")" "${profession_id}"
    mark_provider_online "${provider_json}"
  done

  service_json="$(create_service_request "${client_json}" "${profession_json}" "${task_json}")"
  service_id="$(jq -r '.id' <<<"${service_json}")"
  jq -e '.id != null' <<<"${service_json}" >/dev/null || {
    echo "Erro: falha ao criar service_requests_new." >&2
    echo "${service_json}" >&2
    exit 1
  }

  mark_service_paid_and_searching "${service_id}" >/dev/null

  if [[ "${CALL_DISPATCH}" == "1" ]]; then
    dispatch_json="$(call_dispatch "${service_id}")"
  else
    dispatch_json='{"skipped":true,"reason":"CALL_DISPATCH=0"}'
  fi

  queue_json="$(fetch_queue "${service_id}")"

  jq -nc \
    --arg address "${ADDRESS}" \
    --arg latitude "${LATITUDE}" \
    --arg longitude "${LONGITUDE}" \
    --arg providers "${PROVIDER_EMAILS_CSV}" \
    --argjson profession "$(jq -c '.' <<<"${profession_json}")" \
    --argjson task "$(jq -c '.' <<<"${task_json}")" \
    --argjson client "$(jq -c '.' <<<"${client_json}")" \
    --argjson service "$(api_get "/rest/v1/service_requests_new?id=eq.${service_id}&select=id,status,payment_status,profession_id,task_id,description,created_at&limit=1" | first_item)" \
    --argjson dispatch "$(jq -c '.' <<<"${dispatch_json}")" \
    --argjson queue "$(jq -c '.' <<<"${queue_json}")" \
    '{
      ok: true,
      scenario: "locksmith_copy_key_paid_dispatch",
      address: $address,
      latitude: $latitude,
      longitude: $longitude,
      provider_emails: ($providers | split(",")),
      profession: $profession,
      task: $task,
      client: $client,
      service: $service,
      dispatch: $dispatch,
      queue: $queue
    }'
}

main "$@"
