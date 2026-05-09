#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "[ci] Checking direct Supabase access in changed Dart files..."
./tool/check_no_direct_supabase.sh --changed

echo "[ci] Running flutter analyze..."
flutter analyze

echo "[ci] Quality gate passed."
