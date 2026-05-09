#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---changed}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Padrões proibidos: acesso direto ao Supabase no cliente Flutter.
# Permitido apenas via BackendApiClient / endpoints REST próprios.
PATTERN='Supabase\.instance\.client\.\(from\|rpc\|channel\)\|\.storage\.from(\|\.functions\.invoke('

WHITELIST_FILE="tool/supabase_direct_access_whitelist.txt"

collect_files_changed() {
  git diff --name-only --diff-filter=ACMRTUXB HEAD -- '*.dart' 2>/dev/null || true
}

collect_files_all() {
  find lib -name '*.dart'
}

if [[ "$MODE" == "--all" ]]; then
  FILES="$(collect_files_all)"
else
  FILES="$(collect_files_changed)"
fi

if [[ -z "${FILES// }" ]]; then
  echo "[check_no_direct_supabase] Nenhum arquivo Dart para verificar (${MODE})."
  exit 0
fi

TMP="$(mktemp)"
printf "%s\n" "$FILES" | while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  if [[ -f "$WHITELIST_FILE" ]] && grep -qxF "$f" "$WHITELIST_FILE"; then
    continue
  fi
  grep -n "$PATTERN" "$f" >> "$TMP" || true
done

if [[ -s "$TMP" ]]; then
  echo "[check_no_direct_supabase] Foram encontrados acessos diretos ao Supabase:" >&2
  cat "$TMP" >&2
  rm -f "$TMP"
  exit 1
fi

rm -f "$TMP"
echo "[check_no_direct_supabase] OK: nenhum acesso direto ao Supabase encontrado (${MODE})."
