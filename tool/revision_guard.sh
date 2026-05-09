#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[revision_guard] 1/8 - Policy check (Supabase config + canonical layout)"
./scripts/supabase_guard.sh check

echo "[revision_guard] 2/8 - Verify unique [functions.api] section in supabase/config.toml"
api_section_count="$(grep -c '^\[functions\.api\]$' supabase/config.toml || true)"
if [[ "${api_section_count}" != "1" ]]; then
  echo "❌ supabase/config.toml inválido: esperado 1 seção [functions.api], encontrado ${api_section_count}."
  exit 1
fi

echo "[revision_guard] 3/8 - No direct Supabase access on changed Dart files"
./tool/check_no_direct_supabase.sh --changed

echo "[revision_guard] 4/8 - Backend-first contract presence checks"
rg -n "activeServiceUi|serviceUi|ui\\.headline|open_for_schedule" \
  supabase/functions/api/index.ts \
  lib/core/home/backend_client_home_state.dart \
  lib/core/tracking/backend_active_service_state.dart \
  lib/features/home/home_screen.dart >/dev/null

echo "[revision_guard] 5/8 - Canonical service-flow contract checks"
rg -n "CanonicalServiceState|DispatchEvent|PixPaymentState|ServiceActorRole|ServiceAction|allowedTransitions|permissions|idempotentActions" \
  lib/core/contracts/service_flow_contract.dart >/dev/null
rg -n "Etapa 1|Etapa 10|Critérios de aceite" \
  docs/SERVICE_FLOW_STAGE_CHECKLIST.md >/dev/null

echo "[revision_guard] 6/8 - Analyze critical files"
dart analyze \
  --no-fatal-warnings \
  lib/core/contracts/service_flow_contract.dart \
  lib/features/home/home_screen.dart \
  lib/features/home/widgets/home_waiting_service_banner.dart \
  lib/features/provider/provider_home_mobile.dart \
  lib/features/provider/widgets/provider_service_card.dart \
  lib/core/home/backend_client_home_state.dart \
  lib/core/tracking/backend_active_service_state.dart \
  lib/core/tracking/backend_tracking_api.dart \
  lib/main.dart

echo "[revision_guard] 7/8 - Strict stage guard (optional: STAGE_ID env)"
if [[ -n "${STAGE_ID:-}" ]]; then
  ./tool/strict_stage_guard.sh --stage "${STAGE_ID}" --changed
else
  echo "[revision_guard] STAGE_ID não definido; pulando strict_stage_guard."
fi

echo "[revision_guard] 8/8 - Changed-files Supabase gate (final)"
./tool/check_no_direct_supabase.sh --changed

echo "✅ revision_guard: OK"
