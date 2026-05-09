#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'EOF'
Uso:
  bin/run_patrol_suite.sh <suite|suite1,suite2,...> <ambiente> [device-id]

Suites:
  busca   -> patrol_test/smoke_app_test.dart
  login   -> patrol_test/login_screen_test.dart
  pix     -> patrol_test/pix_payment_screen_test.dart

Pacotes:
  all     -> busca,login,pix

Ambientes:
  emulator
  phone

Exemplos:
  bin/run_patrol_suite.sh busca emulator emulator-5554
  bin/run_patrol_suite.sh login phone ZF524PNH5V
  bin/run_patrol_suite.sh pix emulator
  bin/run_patrol_suite.sh busca,login,pix emulator
  bin/run_patrol_suite.sh all emulator
EOF
}

if [[ "${1:-}" == "" || "${2:-}" == "" ]]; then
  usage
  exit 1
fi

SUITE_INPUT="$1"
ENVIRONMENT="$2"
DEVICE_ID="${3:-}"

APP_SERVER_PORT="8083"
TEST_SERVER_PORT=""

case "$ENVIRONMENT" in
  emulator)
    DEVICE_ID="${DEVICE_ID:-emulator-5554}"
    ;;
  phone)
    DEVICE_ID="${DEVICE_ID:-ZF524PNH5V}"
    TEST_SERVER_PORT="8084"
    ;;
  *)
    echo "Ambiente desconhecido: $ENVIRONMENT"
    usage
    exit 1
    ;;
esac

resolve_suite() {
  local suite_key="$1"
  case "$suite_key" in
    busca)
      SUITE_TARGET="patrol_test/smoke_app_test.dart"
      SUITE_DESCRIPTION="Abre Buscar serviços, valida a barra principal e digita no campo de busca."
      ;;
    login)
      SUITE_TARGET="patrol_test/login_screen_test.dart"
      SUITE_DESCRIPTION="Abre a tela de login, preenche email/senha e valida a resposta do ambiente controlado."
      ;;
    pix)
      SUITE_TARGET="patrol_test/pix_payment_screen_test.dart"
      SUITE_DESCRIPTION="Abre Pagamento Pix, valida dados da cobrança e copia o código Pix."
      ;;
    *)
      echo "Suite desconhecida: $suite_key"
      exit 1
      ;;
  esac
}

if [[ "$SUITE_INPUT" == "all" ]]; then
  SUITE_INPUT="busca,login,pix"
fi

IFS=',' read -r -a SUITES <<< "$SUITE_INPUT"

if [[ ${#SUITES[@]} -eq 0 ]]; then
  echo "Nenhuma suite informada."
  usage
  exit 1
fi

LOG_DIR="$ROOT_DIR/build/patrol_logs"
mkdir -p "$LOG_DIR"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SUMMARY_FILE="$LOG_DIR/pacote_${ENVIRONMENT}_${TIMESTAMP}.summary.txt"

declare -a PASSED_SUITES=()
declare -a FAILED_SUITES=()
declare -a ENVIRONMENT_FAILURES=()

is_device_attached() {
  adb devices | awk 'NR > 1 && $1 == "'"$DEVICE_ID"'" && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'
}

echo "============================================================"
echo "PACOTE DE EXECUCAO PATROL"
echo "Suites:       ${SUITES[*]}"
echo "Ambiente:     $ENVIRONMENT"
echo "Device:       $DEVICE_ID"
echo "Resumo final: $SUMMARY_FILE"
echo "============================================================"
echo

if ! is_device_attached; then
  echo "ERRO DE AMBIENTE: o dispositivo $DEVICE_ID nao esta anexado ao ADB."
  echo "Confira com: adb devices"
  if [[ "$ENVIRONMENT" == "emulator" ]]; then
    echo "Para subir o emulador: flutter emulators --launch Pixel_6"
  fi
  exit 2
fi

for SUITE_KEY in "${SUITES[@]}"; do
  if ! is_device_attached; then
    echo "ERRO DE AMBIENTE: o dispositivo $DEVICE_ID desconectou antes da suite $SUITE_KEY."
    ENVIRONMENT_FAILURES+=("$SUITE_KEY")
    break
  fi

  resolve_suite "$SUITE_KEY"
  LOG_FILE="$LOG_DIR/${SUITE_KEY}_${ENVIRONMENT}_${TIMESTAMP}.log"

  COMMAND=(
    env
    "PATH=$HOME/.pub-cache/bin:/snap/bin:/usr/bin:/bin"
    "PATROL_ANALYTICS_ENABLED=false"
    "PATROL_FLUTTER_COMMAND=/snap/bin/flutter"
    patrol
    test
    --target "$SUITE_TARGET"
    --device "$DEVICE_ID"
    --app-server-port "$APP_SERVER_PORT"
  )

  if [[ -n "$TEST_SERVER_PORT" ]]; then
    COMMAND+=(--test-server-port "$TEST_SERVER_PORT")
  fi

  echo "------------------------------------------------------------"
  echo "SUITE:        $SUITE_KEY"
  echo "ARQUIVO:      $SUITE_TARGET"
  echo "O QUE TESTA:  $SUITE_DESCRIPTION"
  echo "LOG:          $LOG_FILE"
  echo "------------------------------------------------------------"
  echo "Executando comando:"
  printf '  %q' "${COMMAND[@]}"
  echo
  echo

  set +e
  "${COMMAND[@]}" 2>&1 | tee "$LOG_FILE"
  STATUS=${PIPESTATUS[0]}
  set -e

  if [[ $STATUS -eq 0 ]]; then
    PASSED_SUITES+=("$SUITE_KEY")
    SUITE_STATUS="PASSOU"
  else
    if grep -q "Device $DEVICE_ID is not attached" "$LOG_FILE"; then
      ENVIRONMENT_FAILURES+=("$SUITE_KEY")
      SUITE_STATUS="FALHOU POR AMBIENTE"
      echo "Dispositivo $DEVICE_ID desconectou durante a suite $SUITE_KEY."
      break
    else
      FAILED_SUITES+=("$SUITE_KEY")
      SUITE_STATUS="FALHOU"
    fi
  fi

  echo
  echo "Resultado da suite $SUITE_KEY: $SUITE_STATUS"
  echo
done

{
  echo "============================================================"
  echo "RESUMO CONSOLIDADO PATROL"
  echo "Ambiente: $ENVIRONMENT"
  echo "Device:   $DEVICE_ID"
  echo "Suites rodadas: ${SUITES[*]}"
  echo
  echo "PASSARAM (${#PASSED_SUITES[@]}):"
  if [[ ${#PASSED_SUITES[@]} -gt 0 ]]; then
    for suite in "${PASSED_SUITES[@]}"; do
      echo "- $suite"
    done
  else
    echo "- nenhuma"
  fi
  echo
  echo "FALHARAM (${#FAILED_SUITES[@]}):"
  if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
    for suite in "${FAILED_SUITES[@]}"; do
      echo "- $suite"
    done
  else
    echo "- nenhuma"
  fi
  echo
  echo "FALHAS DE AMBIENTE/DISPOSITIVO (${#ENVIRONMENT_FAILURES[@]}):"
  if [[ ${#ENVIRONMENT_FAILURES[@]} -gt 0 ]]; then
    for suite in "${ENVIRONMENT_FAILURES[@]}"; do
      echo "- $suite"
    done
  else
    echo "- nenhuma"
  fi
  echo
  echo "Logs individuais:"
  for suite in "${SUITES[@]}"; do
    echo "- $LOG_DIR/${suite}_${ENVIRONMENT}_${TIMESTAMP}.log"
  done
  echo "============================================================"
} | tee "$SUMMARY_FILE"

if [[ ${#ENVIRONMENT_FAILURES[@]} -gt 0 ]]; then
  exit 2
fi

if [[ ${#FAILED_SUITES[@]} -gt 0 ]]; then
  exit 1
fi

exit 0
