#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPABASE_DIR="$ROOT_DIR/../supabase"

if ! command -v supabase >/dev/null 2>&1; then
  echo "[build_install_apk_local] Erro: supabase CLI não encontrado."
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "[build_install_apk_local] Erro: adb não encontrado."
  exit 1
fi

LAN_IP=$(hostname -I | awk '{print $1}')
if [ -z "${LAN_IP:-}" ]; then
  echo "[build_install_apk_local] Erro: não foi possível detectar IP da máquina."
  exit 1
fi

cd "$SUPABASE_DIR"
ENV_OUT=$(supabase status -o env)
SUPABASE_ANON_KEY=$(printf '%s\n' "$ENV_OUT" | grep '^ANON_KEY=' | sed 's/^ANON_KEY="\(.*\)"$/\1/')
SUPABASE_URL="http://${LAN_IP}:54321"
HOME_AD_HEIGHT="${HOME_AD_HEIGHT:-260}"
HOME_AD_API_URL="${HOME_AD_API_URL:-http://${LAN_IP}:3000/api/marketing/placement/home-banner}"

echo "[build_install_apk_local] SUPABASE_URL=${SUPABASE_URL}"
echo "[build_install_apk_local] HOME_AD_API_URL=${HOME_AD_API_URL}"
echo "[build_install_apk_local] HOME_AD_HEIGHT=${HOME_AD_HEIGHT}"
echo "[build_install_apk_local] Importante: celular e PC devem estar na mesma rede Wi-Fi."

cd "$ROOT_DIR"
flutter build apk --debug \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=HOME_AD_API_URL="$HOME_AD_API_URL" \
  --dart-define=HOME_AD_HEIGHT="$HOME_AD_HEIGHT"

APK_PATH="$ROOT_DIR/build/app/outputs/flutter-apk/app-debug.apk"
if [ ! -f "$APK_PATH" ]; then
  echo "[build_install_apk_local] Erro: APK não encontrado em $APK_PATH"
  exit 1
fi

DEVICE_SERIAL=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
if [ -z "${DEVICE_SERIAL:-}" ]; then
  echo "[build_install_apk_local] Erro: nenhum dispositivo Android conectado."
  exit 1
fi

echo "[build_install_apk_local] Instalando APK em ${DEVICE_SERIAL}..."
adb -s "$DEVICE_SERIAL" install -r "$APK_PATH"

echo "[build_install_apk_local] APK instalado com sucesso."
echo "[build_install_apk_local] App aponta para Supabase local em ${SUPABASE_URL}"
