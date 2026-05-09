#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f "supabase/.env.deploy" ]]; then
  echo "[run_web_remote] Erro: arquivo supabase/.env.deploy não encontrado."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "[run_web_remote] Erro: flutter não encontrado no PATH."
  exit 1
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "[run_web_remote] Erro: supabase CLI não encontrado no PATH."
  exit 1
fi

cd "$ROOT_DIR/supabase"
if ! supabase status >/dev/null 2>&1; then
  echo "[run_web_remote] Supabase local não está rodando. Subindo automaticamente..."
  supabase start
fi
cd "$ROOT_DIR"

set -a
source "supabase/.env.deploy"
set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "[run_web_remote] Erro: SUPABASE_URL/SUPABASE_ANON_KEY ausentes em supabase/.env.deploy."
  exit 1
fi

if [[ -z "${BACKEND_API_URL:-}" ]]; then
  echo "[run_web_remote] Erro: BACKEND_API_URL ausente em supabase/.env.deploy."
  exit 1
fi

WEB_PORT="${WEB_PORT:-51300}"
HOME_AD_HEIGHT="${HOME_AD_HEIGHT:-260}"
MARKETING_HOST="${MARKETING_HOST:-127.0.0.1}"
HOME_AD_API_URL_DEFAULT="http://${MARKETING_HOST}:3000/api/marketing/embed/home-banner"
TRACKING_AD_API_URL_DEFAULT="http://${MARKETING_HOST}:3000/api/marketing/embed/tracking-banner"
HOME_AD_API_URL="${HOME_AD_API_URL:-$HOME_AD_API_URL_DEFAULT}"
TRACKING_AD_API_URL="${TRACKING_AD_API_URL:-$TRACKING_AD_API_URL_DEFAULT}"

if command -v fuser >/dev/null 2>&1; then
  fuser -k "${WEB_PORT}/tcp" >/dev/null 2>&1 || true
fi

echo "[run_web_remote] Iniciando Flutter Web em http://127.0.0.1:${WEB_PORT}"
echo "[run_web_remote] SUPABASE_URL=${SUPABASE_URL}"
echo "[run_web_remote] BACKEND_API_URL=${BACKEND_API_URL}"
echo "[run_web_remote] HOME_AD_API_URL=${HOME_AD_API_URL}"

flutter run -d chrome \
  --web-port="${WEB_PORT}" \
  --web-browser-flag=--ignore-gpu-blocklist \
  --web-browser-flag=--use-gl=swiftshader \
  --web-browser-flag=--enable-unsafe-swiftshader \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=BACKEND_API_URL="${BACKEND_API_URL}" \
  --dart-define=HOME_AD_API_URL="${HOME_AD_API_URL}" \
  --dart-define=TRACKING_AD_API_URL="${TRACKING_AD_API_URL}" \
  --dart-define=HOME_AD_HEIGHT="${HOME_AD_HEIGHT}" \
  --dart-define=BOOKING_PIX_REAL=true
