#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

STAGE=""
MODE="--changed"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --stage)
      STAGE="${2:-}"
      shift 2
      ;;
    --all)
      MODE="--all"
      shift
      ;;
    --changed)
      MODE="--changed"
      shift
      ;;
    *)
      echo "Uso: $0 --stage <stage_id> [--changed|--all]"
      exit 1
      ;;
  esac
done

if [[ -z "$STAGE" ]]; then
  echo "❌ Stage obrigatório. Exemplo: ./tool/strict_stage_guard.sh --stage stage_01_contract"
  exit 1
fi

ALLOWLIST_FILE="tool/stage_allowlists/${STAGE}.txt"
if [[ ! -f "$ALLOWLIST_FILE" ]]; then
  echo "❌ Allowlist não encontrada: $ALLOWLIST_FILE"
  exit 1
fi

collect_changed() {
  git diff --name-only --diff-filter=ACMRTUXB HEAD 2>/dev/null || true
}

collect_all_tracked() {
  git ls-files
}

if [[ "$MODE" == "--all" ]]; then
  FILES="$(collect_all_tracked)"
else
  FILES="$(collect_changed)"
fi

if [[ -z "${FILES// }" ]]; then
  echo "[strict_stage_guard] Nenhum arquivo para validar (${MODE})."
  exit 0
fi

is_allowed() {
  local f="$1"
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    [[ "$rule" =~ ^# ]] && continue

    if [[ "$rule" == */ ]]; then
      [[ "$f" == "$rule"* ]] && return 0
    elif [[ "$rule" == *"*"* ]]; then
      local prefix="${rule%%\**}"
      [[ "$f" == "$prefix"* ]] && return 0
    else
      [[ "$f" == "$rule" ]] && return 0
    fi
  done < "$ALLOWLIST_FILE"
  return 1
}

violations=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if ! is_allowed "$f"; then
    violations+="$f"$'\n'
  fi
done <<< "$FILES"

if [[ -n "$violations" ]]; then
  echo "❌ strict stage lock falhou para stage '$STAGE'."
  echo "Arquivos fora da allowlist:"
  printf '%s' "$violations"
  echo
  echo "Allowlist aplicada: $ALLOWLIST_FILE"
  exit 1
fi

echo "✅ strict stage lock OK (${STAGE}, ${MODE})."
