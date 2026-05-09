#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TARGET_DIR="lib"

# Diretivas proibidas para evitar acesso direto do app ao Supabase.
PATTERN="(Supabase\.instance\.client\.(from|rpc|channel)\(|Supabase\.instance\.client\.functions\.invoke\(|\b(supabase|_supa|client)\.(from|rpc|channel)\(|\b(supabase|_supa|client)\.functions\.invoke\(|^\s*\.from\('|^\s*\.rpc\('|^\s*\.channel\(|^\s*\.functions\.invoke\(|\.storage\.from\()"

matches=$(rg -n "$PATTERN" "$TARGET_DIR" || true)
if [[ -z "${matches}" ]]; then
  echo "✅ Sem uso direto proibido de Supabase em $TARGET_DIR"
  exit 0
fi

echo "❌ Encontrado uso direto de Supabase fora da whitelist:"
echo "$matches"
exit 1
