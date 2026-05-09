#!/usr/bin/env bash
set -euo pipefail

# Guard rail para evitar deploy no diretório Supabase errado.
# Uso:
#   ./scripts/supabase_guard.sh check
#   ./scripts/supabase_guard.sh deploy api post_action get-available-services

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../" && pwd)"
CANONICAL_SUPABASE_DIR="$ROOT_DIR/supabase"
MOBILE_SUPABASE_DIR="$ROOT_DIR/mobile_app/supabase"

fail() {
  echo "❌ $1" >&2
  exit 1
}

info() {
  echo "ℹ️  $1"
}

check_layout() {
  [[ -d "$CANONICAL_SUPABASE_DIR/functions" ]] || fail "Não encontrei functions em $CANONICAL_SUPABASE_DIR"
  [[ -f "$CANONICAL_SUPABASE_DIR/config.toml" ]] || fail "Não encontrei config.toml canônico em $CANONICAL_SUPABASE_DIR"
  [[ -f "$CANONICAL_SUPABASE_DIR/.temp/project-ref" ]] || fail "Não encontrei .temp/project-ref em $CANONICAL_SUPABASE_DIR"

  local ref
  ref="$(cat "$CANONICAL_SUPABASE_DIR/.temp/project-ref" | tr -d '\n\r')"
  [[ -n "$ref" ]] || fail "project-ref vazio em $CANONICAL_SUPABASE_DIR/.temp/project-ref"

  info "Supabase canônico: $CANONICAL_SUPABASE_DIR"
  info "project-ref: $ref"

  if [[ -d "$MOBILE_SUPABASE_DIR/functions" ]]; then
    info "Supabase local (mobile_app): $MOBILE_SUPABASE_DIR"
    info "Atenção: mantenha essa pasta apenas como apoio local; deploy oficial usa $CANONICAL_SUPABASE_DIR"
  fi

  check_api_verify_jwt_policy
}

check_api_verify_jwt_policy() {
  local cfg="$CANONICAL_SUPABASE_DIR/config.toml"
  [[ -f "$cfg" ]] || fail "config.toml não encontrado em $cfg"

  if ! awk '
    BEGIN { in_api=0; ok=0 }
    /^\[functions\.api\]$/ { in_api=1; next }
    /^\[/ && $0 !~ /^\[functions\.api\]$/ { in_api=0 }
    in_api && $0 ~ /^verify_jwt[[:space:]]*=[[:space:]]*false[[:space:]]*$/ { ok=1 }
    END { exit(ok?0:1) }
  ' "$cfg"; then
    fail "Política obrigatória violada: [functions.api] verify_jwt = false"
  fi

  info "Política JWT OK: [functions.api] verify_jwt = false"
}

deploy_functions() {
  local ref
  ref="$(cat "$CANONICAL_SUPABASE_DIR/.temp/project-ref" | tr -d '\n\r')"
  [[ -n "$ref" ]] || fail "project-ref ausente para deploy."

  [[ "$#" -gt 0 ]] || fail "Informe ao menos uma função para deploy."

  for fn in "$@"; do
    [[ -f "$CANONICAL_SUPABASE_DIR/functions/$fn/index.ts" ]] || fail "Função '$fn' não encontrada em $CANONICAL_SUPABASE_DIR/functions/$fn/index.ts"
    info "Deploy: $fn -> $ref"
    supabase --workdir "$ROOT_DIR" functions deploy "$fn" --project-ref "$ref"
  done
}

cmd="${1:-check}"
shift || true

case "$cmd" in
  check)
    check_layout
    ;;
  deploy)
    check_layout
    deploy_functions "$@"
    ;;
  *)
    fail "Comando inválido: $cmd (use: check | deploy)"
    ;;
esac
