#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import os
from collections import Counter, defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[1]
TARGET_DIRS = [ROOT / "lib", ROOT.parent / "supabase" / "functions"]
TARGET_TABLES = {
    "service_requests",
    "service_requests_new",
    "notificacao_de_servicos",
    "service_dispatch_queue",
    "payments",
    "fixed_booking_pix_intents",
    "provider_locations",
    "users",
}

FROM_RE = re.compile(r"\.from\(\s*['\"]([a-zA-Z0-9_\-]+)['\"]\s*\)")
CHAIN_SELECT_RE = re.compile(
    r"\.from\(\s*['\"]([a-zA-Z0-9_\-]+)['\"]\s*\)(?:(?!\.from\().){0,1200}?\.select\(\s*['\"]([^'\"]+)['\"]\s*\)",
    re.DOTALL,
)


def iter_files():
    for base in TARGET_DIRS:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.suffix.lower() in {".dart", ".ts"} and p.is_file():
                yield p


def parse_cols(select_expr: str) -> list[str]:
    cols = []
    for raw in select_expr.split(","):
        c = raw.strip()
        if not c or c == "*":
            continue
        c = re.sub(r"\s+", "", c)
        if "(" in c and ")" in c:
            # Ex: providers(id,name)
            base = c.split("(", 1)[0]
            if base:
                cols.append(base)
            continue
        c = c.split(":", 1)[-1]
        cols.append(c)
    return cols


def main():
    table_count = Counter()
    table_files = defaultdict(set)
    table_cols = defaultdict(Counter)

    for f in iter_files():
        txt = f.read_text(encoding="utf-8", errors="ignore")

        for m in FROM_RE.finditer(txt):
            t = m.group(1)
            table_count[t] += 1
            table_files[t].add(os.path.relpath(str(f), str(ROOT)))

        for m in CHAIN_SELECT_RE.finditer(txt):
            table = m.group(1)
            expr = m.group(2)
            for col in parse_cols(expr):
                table_cols[table][col] += 1

    print("=== TABELAS REFERENCIADAS (lib + supabase/functions) ===")
    for t, n in table_count.most_common():
        print(f"{t}: {n}")

    print("\n=== TABELAS-ALVO (USO) ===")
    for t in sorted(TARGET_TABLES):
        print(f"- {t}: refs={table_count.get(t, 0)} arquivos={len(table_files.get(t, []))}")

    print("\n=== COLUNAS REFERENCIADAS POR TABELA-ALVO (cadeia from().select()) ===")
    for t in sorted(TARGET_TABLES):
        cols = table_cols.get(t, Counter())
        print(f"\n[{t}]")
        if not cols:
            print("  (sem colunas extraídas por cadeia from().select())")
            continue
        for c, n in cols.most_common():
            print(f"  {c}: {n}")


if __name__ == "__main__":
    main()
