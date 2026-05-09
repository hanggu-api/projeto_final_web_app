#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import urllib.error
import urllib.parse
import urllib.request

REQUIRED_COLUMNS = [
    "id",
    "status",
    "provider_id",
    "created_at",
    "updated_at",
    "status_updated_at",
    "payment_status",
    "payment_remaining_status",
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


def req_json(url: str, headers: dict, method: str = "GET", body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, headers=headers, method=method, data=data)
    with urllib.request.urlopen(req, timeout=30) as r:
        raw = r.read().decode("utf-8")
        return json.loads(raw) if raw else {}


def req_json_safe(url: str, headers: dict, method: str = "GET", body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, headers=headers, method=method, data=data)
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


def reactivate_service_for_dispatch(url: str, headers: dict, service_id: str) -> dict:
    sid_q = urllib.parse.quote(service_id, safe="")
    now_expr = "now()"

    service_req_url = (
        f"{url}/rest/v1/service_requests"
        f"?id=eq.{sid_q}&provider_id=is.null"
    )
    service_payload = {
        "status": "searching_provider",
        "status_updated_at": now_expr,
        "updated_at": now_expr,
    }
    _, service_err = req_json_safe(
        service_req_url,
        headers,
        method="PATCH",
        body=service_payload,
    )

    notif_url = f"{url}/rest/v1/notificacao_de_servicos?service_id=eq.{sid_q}"
    notif_payload = {
        "status": "queued",
        "last_notified_at": None,
        "response_deadline_at": None,
        "answered_at": None,
        "push_status": None,
        "push_error_code": None,
        "push_error_type": None,
        "skip_reason": None,
        "locked_at": None,
        "locked_by_run": None,
    }
    _, notif_err = req_json_safe(
        notif_url,
        headers,
        method="PATCH",
        body=notif_payload,
    )

    queue_url = f"{url}/rest/v1/service_dispatch_queue?on_conflict=service_id"
    queue_payload = {
        "service_id": service_id,
        "status": "pending",
        "next_run_at": now_expr,
        "attempts": 0,
        "updated_at": now_expr,
    }
    _, queue_err = req_json_safe(
        queue_url,
        headers,
        method="POST",
        body=queue_payload,
    )

    return {
        "service_request_patch_error": service_err,
        "notificacao_patch_error": notif_err,
        "dispatch_queue_upsert_error": queue_err,
        "ok": all(e is None for e in [service_err, notif_err, queue_err]),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Verifica saúde do fluxo de serviço e pode reativar notificação.")
    parser.add_argument("service_id", nargs="?", help="ID do serviço específico")
    parser.add_argument(
        "--reactivate-last",
        action="store_true",
        help="Pega o último serviço (created_at desc) e reativa para notificação",
    )
    parser.add_argument(
        "--reactivate",
        action="store_true",
        help="Reativa para notificação o serviço encontrado/fornecido",
    )
    args = parser.parse_args()

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
        "Prefer": "return=representation,resolution=merge-duplicates",
    }

    service_id = args.service_id
    if args.reactivate_last and service_id:
        print("⚠️ Use apenas um: service_id OU --reactivate-last")
        return 1

    select = ",".join(REQUIRED_COLUMNS)
    if service_id:
        q = urllib.parse.urlencode({"select": select, "id": f"eq.{service_id}", "limit": "1"})
    else:
        q = f"select={select}&order=created_at.desc&limit=1"

    endpoint = f"{url}/rest/v1/service_requests?{q}"
    try:
        rows = req_json(endpoint, headers)
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8", errors="ignore")
        print(f"❌ Falha ao consultar service_requests: HTTP {e.code}\n{payload}")
        return 2

    if not rows:
        print("⚠️ Nenhum serviço encontrado")
        return 3

    row = rows[0]
    sid = row.get("id")
    print("✅ Colunas essenciais OK em service_requests")
    print(json.dumps(row, ensure_ascii=False, indent=2))

    if args.reactivate or args.reactivate_last:
        print(f"\n🔁 Reativando serviço para notificação: {sid}")
        reactivate_result = reactivate_service_for_dispatch(url, headers, sid)
        print(json.dumps(reactivate_result, ensure_ascii=False, indent=2))

    table_projection_fallbacks = {
        "users": [
            "id,role,fcm_token,last_seen_at,supabase_uid",
            "id,role,fcm_token,last_seen_at",
            "id,role,fcm_token",
        ],
        "service_dispatch_queue": [
            "service_id,status,updated_at,next_run_at,attempts",
            "service_id,status,next_run_at,attempts",
            "service_id,status",
            "id,service_id,status",
        ],
        "notificacao_de_servicos": [
            "service_id,status,updated_at,last_notified_at,response_deadline_at,push_status,push_error_code",
            "service_id,status,last_notified_at,response_deadline_at,push_status,push_error_code",
            "service_id,status,last_notified_at",
            "id,service_id,status",
        ],
    }

    for table in ["service_dispatch_queue", "notificacao_de_servicos"]:
        rows = None
        last_err = None
        for projection in table_projection_fallbacks.get(table, ["*"]):
            q2 = urllib.parse.urlencode(
                {"select": projection, "service_id": f"eq.{sid}", "limit": "5"},
            )
            u2 = f"{url}/rest/v1/{table}?{q2}"
            out, err = req_json_safe(u2, headers)
            if err is None:
                rows = out
                break
            if str(err.get("code", "")) == "42703":
                last_err = err
                continue
            last_err = err
            break

        if rows is not None:
            print(f"\n📊 {table}: {len(rows)} registro(s)")
            print(json.dumps(rows[:5], ensure_ascii=False, indent=2))
            continue

        print(f"\n⚠️ {table}: não foi possível consultar")
        if last_err:
            print(json.dumps(last_err, ensure_ascii=False, indent=2))

    provider_id = row.get("provider_id")
    if provider_id is not None:
        rows = None
        last_err = None
        for projection in table_projection_fallbacks.get("users", ["*"]):
            q2 = urllib.parse.urlencode(
                {"select": projection, "id": f"eq.{provider_id}", "limit": "1"},
            )
            u2 = f"{url}/rest/v1/users?{q2}"
            out, err = req_json_safe(u2, headers)
            if err is None:
                rows = out
                break
            if str(err.get("code", "")) == "42703":
                last_err = err
                continue
            last_err = err
            break

        if rows is not None:
            safe_rows = []
            for item in rows[:1]:
                safe_item = dict(item)
                token = str(safe_item.get("fcm_token") or "").strip()
                safe_item["fcm_token_present"] = bool(token)
                safe_item["fcm_token_masked"] = (
                    f"{token[:6]}...{token[-6:]}" if len(token) > 12 else token
                ) if token else ""
                safe_item.pop("fcm_token", None)
                safe_rows.append(safe_item)
            print(f"\n📱 users/provider token: {len(safe_rows)} registro(s)")
            print(json.dumps(safe_rows, ensure_ascii=False, indent=2))
        elif last_err:
            print("\n⚠️ users/provider token: não foi possível consultar")
            print(json.dumps(last_err, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
