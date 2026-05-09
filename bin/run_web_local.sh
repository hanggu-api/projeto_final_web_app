#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_DIR="$ROOT_DIR/../supabase"
WEB_PORT="${WEB_PORT:-51300}"
HOME_AD_HEIGHT="${HOME_AD_HEIGHT:-260}"
MARKETING_HOST="${MARKETING_HOST:-127.0.0.1}"
HOME_AD_API_URL_DEFAULT="http://${MARKETING_HOST}:3000/api/marketing/placement/home-banner"
HOME_AD_API_URL="${HOME_AD_API_URL:-$HOME_AD_API_URL_DEFAULT}"
USE_REMOTE_BACKEND="${USE_REMOTE_BACKEND:-false}"
USE_REMOTE_SUPABASE="${USE_REMOTE_SUPABASE:-false}"

if ! command -v supabase >/dev/null 2>&1; then
  echo "[run_web_local] Erro: supabase CLI não encontrado no PATH."
  exit 1
fi

if [[ "${USE_REMOTE_SUPABASE}" == "true" ]]; then
  if [[ -f "$ROOT_DIR/../supabase/.env.deploy" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      key="${line%%=*}"
      value="${line#*=}"
      key="$(echo "$key" | xargs)"
      [[ -z "$key" ]] && continue
      export "$key=$value"
    done < "$ROOT_DIR/../supabase/.env.deploy"
  fi
  if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
    echo "[run_web_local] Erro: USE_REMOTE_SUPABASE=true exige SUPABASE_URL e SUPABASE_ANON_KEY no ambiente."
    exit 1
  fi
else
  cd "$SUPABASE_DIR"
  # Garante que o stack local do Supabase esteja em execução.
  if ! supabase status >/dev/null 2>&1; then
    echo "[run_web_local] Supabase local não está rodando. Subindo automaticamente..."
    supabase start
  fi

  ENV_OUT=$(supabase status -o env)
  SUPABASE_URL=$(printf '%s\n' "$ENV_OUT" | grep '^API_URL=' | sed 's/^API_URL="\(.*\)"$/\1/')
  SUPABASE_ANON_KEY=$(printf '%s\n' "$ENV_OUT" | grep '^ANON_KEY=' | sed 's/^ANON_KEY="\(.*\)"$/\1/')
fi

cd "$ROOT_DIR"
if command -v fuser >/dev/null 2>&1; then
  fuser -k "${WEB_PORT}/tcp" >/dev/null 2>&1 || true
fi

echo "[run_web_local] Iniciando Flutter Web em http://127.0.0.1:${WEB_PORT}"
echo "[run_web_local] SUPABASE_URL=$SUPABASE_URL"
echo "[run_web_local] HOME_AD_API_URL=$HOME_AD_API_URL"
echo "[run_web_local] HOME_AD_HEIGHT=$HOME_AD_HEIGHT"

if [[ "${USE_REMOTE_BACKEND}" == "true" ]]; then
  if [[ -z "${BACKEND_API_URL:-}" ]]; then
    echo "[run_web_local] Erro: USE_REMOTE_BACKEND=true exige BACKEND_API_URL no ambiente."
    exit 1
  fi
  if [[ "${BACKEND_API_URL}" == "https://SEU_BACKEND_ONLINE" ]]; then
    echo "[run_web_local] Erro: BACKEND_API_URL está com placeholder (https://SEU_BACKEND_ONLINE)."
    echo "[run_web_local] Defina a URL real do backend remoto em supabase/.env.deploy."
    exit 1
  fi
  echo "[run_web_local] BACKEND_API_URL=$BACKEND_API_URL"
  flutter run -d chrome \
    --web-port="${WEB_PORT}" \
    --web-browser-flag=--ignore-gpu-blocklist \
    --web-browser-flag=--use-gl=swiftshader \
    --web-browser-flag=--enable-unsafe-swiftshader \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --dart-define=BACKEND_API_URL="$BACKEND_API_URL" \
    --dart-define=HOME_AD_API_URL="$HOME_AD_API_URL" \
    --dart-define=HOME_AD_HEIGHT="$HOME_AD_HEIGHT"
else
  flutter run -d chrome \
    --web-port="${WEB_PORT}" \
    --web-browser-flag=--ignore-gpu-blocklist \
    --web-browser-flag=--use-gl=swiftshader \
    --web-browser-flag=--enable-unsafe-swiftshader \
    --dart-define=SUPABASE_URL="$SUPABASE_URL" \
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
    --dart-define=HOME_AD_API_URL="$HOME_AD_API_URL" \
    --dart-define=HOME_AD_HEIGHT="$HOME_AD_HEIGHT"
fi
