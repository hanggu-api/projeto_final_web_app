#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -f "supabase/.env.deploy" ]]; then
  echo "[run_android_remote] Erro: arquivo supabase/.env.deploy não encontrado."
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "[run_android_remote] Erro: flutter não encontrado no PATH."
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "[run_android_remote] Erro: adb não encontrado no PATH."
  exit 1
fi

if ! command -v supabase >/dev/null 2>&1; then
  echo "[run_android_remote] Erro: supabase CLI não encontrado no PATH."
  exit 1
fi

cd "$ROOT_DIR/supabase"
if ! supabase status >/dev/null 2>&1; then
  echo "[run_android_remote] Supabase local não está rodando. Subindo automaticamente..."
  supabase start
fi
cd "$ROOT_DIR"

set -a
source "supabase/.env.deploy"
set +a

if [[ -z "${SUPABASE_URL:-}" || -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "[run_android_remote] Erro: SUPABASE_URL/SUPABASE_ANON_KEY ausentes em supabase/.env.deploy."
  exit 1
fi

if [[ -z "${BACKEND_API_URL:-}" ]]; then
  echo "[run_android_remote] Erro: BACKEND_API_URL ausente em supabase/.env.deploy."
  exit 1
fi

DEVICE_SERIAL="${1:-$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')}"
if [[ -z "${DEVICE_SERIAL}" ]]; then
  echo "[run_android_remote] Erro: nenhum dispositivo Android conectado."
  exit 1
fi

HOME_AD_API_URL_DEFAULT="http://192.168.1.5:3000/api/marketing/embed/home-banner"
TRACKING_AD_API_URL_DEFAULT="http://192.168.1.5:3000/api/marketing/embed/tracking-banner"

HOME_AD_API_URL="${HOME_AD_API_URL:-$HOME_AD_API_URL_DEFAULT}"
TRACKING_AD_API_URL="${TRACKING_AD_API_URL:-$TRACKING_AD_API_URL_DEFAULT}"
HOME_AD_HEIGHT="${HOME_AD_HEIGHT:-260}"

echo "[run_android_remote] Dispositivo: ${DEVICE_SERIAL}"
echo "[run_android_remote] SUPABASE_URL=${SUPABASE_URL}"
echo "[run_android_remote] BACKEND_API_URL=${BACKEND_API_URL}"
echo "[run_android_remote] HOME_AD_API_URL=${HOME_AD_API_URL}"

flutter run -d "${DEVICE_SERIAL}" \
  --dart-define=SUPABASE_URL="${SUPABASE_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=BACKEND_API_URL="${BACKEND_API_URL}" \
  --dart-define=HOME_AD_API_URL="${HOME_AD_API_URL}" \
  --dart-define=TRACKING_AD_API_URL="${TRACKING_AD_API_URL}" \
  --dart-define=HOME_AD_HEIGHT="${HOME_AD_HEIGHT}" \
  --dart-define=BOOKING_PIX_REAL=true
