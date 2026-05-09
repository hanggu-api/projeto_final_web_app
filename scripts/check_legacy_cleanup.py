#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

DROPPED_EXPECTED = [
    "app_config",
    "categories",
    "service_tasks",
    "service_media",
    "notification_registry",
    "transactions",
    "user_devices",
]

CRITICAL_EXPECTED = [
    "service_requests",
    "service_dispatch_queue",
    "notificacao_de_servicos",
    "payments",
    "users",
    "provider_locations",
]


def load_env_local() -> None:
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    for p in [os.path.join(root, ".env.local"), os.path.join(root, "scripts", ".env.local")]:
        if not os.path.isfile(p):
            continue
        with open(p, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k not in os.environ:
                    os.environ[k.strip()] = v.strip().strip('"').strip("'")


def req_json_safe(url: str, headers: dict, method: str = "GET"):
    req = urllib.request.Request(url, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode("utf-8")
            return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8", errors="ignore")
        try:
            err = json.loads(payload) if payload else {}
        except Exception:
            err = {"message": payload}
        err["_status"] = e.code
        return None, err
    except urllib.error.URLError as e:
        return None, {"_status": 0, "code": "NETWORK_ERROR", "message": str(e)}


def table_probe(url_base: str, headers: dict, table: str) -> tuple[bool, dict | None]:
    query = urllib.parse.urlencode({"select": "id", "limit": "1"})
    url = f"{url_base}/rest/v1/{table}?{query}"
    data, err = req_json_safe(url, headers)
    if err is None:
        return True, None

    # Tabela não existe / não exposta
    if str(err.get("code", "")) == "PGRST205":
        return False, err

    # Tabela existe mas pode não ter coluna id; tenta fallback com '*'
    if str(err.get("code", "")) == "42703":
        query2 = urllib.parse.urlencode({"select": "*", "limit": "1"})
        data2, err2 = req_json_safe(f"{url_base}/rest/v1/{table}?{query2}", headers)
        if err2 is None:
            return True, None
        if str(err2.get("code", "")) == "PGRST205":
            return False, err2
        return False, err2

    return False, err


def main() -> int:
    load_env_local()
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "") or os.getenv("SERVICE_ROLE_KEY", "")
    if not url or not key:
        print("❌ Configure SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY")
        return 1

    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }

    errors = []

    print("🔎 Verificando tabelas que DEVEM ter sido removidas...")
    for t in DROPPED_EXPECTED:
        exists, err = table_probe(url, headers, t)
        if exists:
            errors.append(f"Tabela legada ainda existe: {t}")
            print(f"❌ {t}: ainda existe")
        else:
            print(f"✅ {t}: removida")

    print("\n🔎 Verificando tabelas críticas que DEVEM existir...")
    for t in CRITICAL_EXPECTED:
        exists, err = table_probe(url, headers, t)
        if not exists:
            errors.append(f"Tabela crítica indisponível: {t} | err={json.dumps(err, ensure_ascii=False)}")
            print(f"❌ {t}: indisponível")
            if err:
                print(json.dumps(err, ensure_ascii=False, indent=2))
        else:
            print(f"✅ {t}: OK")

    if errors:
        print("\n❌ Cleanup com pendências:")
        for e in errors:
            print(f"- {e}")
        return 2

    print("\n✅ Cleanup validado com sucesso.")
    print("ℹ️ Para validar backups em legacy_backup, rode via SQL CLI:")
    print("   supabase db query \"select schemaname, tablename from pg_tables where schemaname='legacy_backup' order by tablename;\"")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
