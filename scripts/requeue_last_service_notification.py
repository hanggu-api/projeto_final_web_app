#!/usr/bin/env python3
"""
Busca o último serviço no banco e, opcionalmente, redispara o dispatch.

Uso:
  export SUPABASE_URL="https://<project>.supabase.co"
  export SUPABASE_SERVICE_ROLE_KEY="<service-role-key>"

  # Ou use arquivo local não versionado (.env.local)
  # SUPABASE_URL=...
  # SUPABASE_SERVICE_ROLE_KEY=...

  # Apenas buscar último serviço
  python3 scripts/requeue_last_service_notification.py

  # Buscar por status elegível e redisparar
  python3 scripts/requeue_last_service_notification.py --redispatch

  # Forçar um service_id específico e redisparar
  python3 scripts/requeue_last_service_notification.py \
    --service-id 7e20fdc6-c82b-46c0-8d9c-40e18881df57 --redispatch

  # Forçar reenvio (limpa histórico de fila/notificação do service_id e redispara)
  python3 scripts/requeue_last_service_notification.py \
    --service-id 7e20fdc6-c82b-46c0-8d9c-40e18881df57 --redispatch --force-requeue

  # Reativar o serviço e reenviar notificações em um passo
  python3 scripts/requeue_last_service_notification.py \
    --service-id 7e20fdc6-c82b-46c0-8d9c-40e18881df57 --resend-notification

  # Pegar automaticamente o último pedido elegível e reenviar
  python3 scripts/requeue_last_service_notification.py --resend-last-notification
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from urllib.parse import quote
from typing import Any

TERMINAL_STATUSES = {
    "completed",
    "cancelled",
    "canceled",
    "expired",
    "refunded",
    "closed",
}

NOTIF_TABLE_CANDIDATES = [
    "registro_de_notificações",
    "registro_de_notificacoes",
    "notificacao_de_servicos",
]

DISPATCH_QUEUE_TABLE_CANDIDATES = [
    "service_dispatch_queue",
    "fila_de_despacho_de_servico",
]


def _load_dotenv_local() -> None:
    """
    Carrega variáveis de .env.local sem sobrescrever env já definido.
    Procura em:
      - <repo>/.env.local
      - <repo>/scripts/.env.local
    """
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    candidates = [
        os.path.join(root_dir, ".env.local"),
        os.path.join(root_dir, "scripts", ".env.local"),
    ]

    for path in candidates:
        if not os.path.isfile(path):
            continue
        with open(path, "r", encoding="utf-8") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip().strip("'").strip('"')
                if key and key not in os.environ:
                    os.environ[key] = value


def _require_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        print(f"❌ Variável obrigatória ausente: {name}", file=sys.stderr)
        sys.exit(1)
    return value


def _request_json(url: str, method: str, headers: dict[str, str], body: dict[str, Any] | None = None) -> Any:
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url=url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8", errors="ignore")
        print(f"❌ HTTP {e.code} em {url}", file=sys.stderr)
        if payload:
            print(payload, file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as e:
        print(f"❌ Erro de rede em {url}: {e}", file=sys.stderr)
        sys.exit(1)


def _request_json_safe(
    url: str,
    method: str,
    headers: dict[str, str],
    body: dict[str, Any] | None = None,
) -> tuple[Any | None, dict[str, Any] | None]:
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")

    req = urllib.request.Request(url=url, method=method, headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return (json.loads(raw) if raw else {}), None
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8", errors="ignore")
        try:
            err_json = json.loads(payload) if payload else {}
        except Exception:
            err_json = {"message": payload or str(e)}
        err_json["_status"] = e.code
        return None, err_json
    except urllib.error.URLError as e:
        return None, {"_status": 0, "message": str(e)}


def _http_get_json_or_error(url: str, headers: dict[str, str]) -> tuple[Any | None, dict[str, Any] | None]:
    req = urllib.request.Request(url=url, method="GET", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return (json.loads(raw) if raw else []), None
    except urllib.error.HTTPError as e:
        payload = e.read().decode("utf-8", errors="ignore")
        try:
            err_json = json.loads(payload) if payload else {}
        except Exception:
            err_json = {"message": payload or str(e)}
        err_json["_status"] = e.code
        return None, err_json
    except urllib.error.URLError as e:
        return None, {"_status": 0, "message": str(e)}


def _fetch_first_row_with_projection_fallback(
    supabase_url: str,
    headers: dict[str, str],
    filters_and_order: str,
    projection_candidates: list[str],
) -> dict[str, Any]:
    last_error: dict[str, Any] | None = None
    for projection in projection_candidates:
        query = f"select={projection}&{filters_and_order}"
        url = f"{supabase_url}/rest/v1/service_requests?{query}"
        rows, err = _http_get_json_or_error(url, headers)
        if err is None:
            if rows:
                return rows[0]
            continue

        # Se for erro de coluna inexistente, tenta próxima projeção.
        if str(err.get("code", "")) == "42703":
            last_error = err
            continue

        status = err.get("_status")
        print(f"❌ HTTP {status} em {url}", file=sys.stderr)
        print(json.dumps(err, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)

    if last_error:
        print("❌ Falha ao consultar service_requests: projeções incompatíveis com o schema atual.", file=sys.stderr)
        print(json.dumps(last_error, ensure_ascii=False), file=sys.stderr)
        sys.exit(1)

    print("❌ Nenhum serviço encontrado na tabela service_requests.", file=sys.stderr)
    sys.exit(1)


def fetch_last_service(supabase_url: str, service_key: str, explicit_service_id: str | None) -> dict[str, Any]:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }
    projection_candidates = [
        "id,status,created_at,updated_at,client_id,provider_id",
        "id,status,created_at,client_id,provider_id",
        "id,status,created_at,client_uid,provider_uid",
        "id,status,created_at",
    ]

    if explicit_service_id:
        id_filter = urllib.parse.urlencode({"id": f"eq.{explicit_service_id}"})
        service = _fetch_first_row_with_projection_fallback(
            supabase_url=supabase_url,
            headers=headers,
            filters_and_order=id_filter,
            projection_candidates=projection_candidates,
        )
        if not service:
            print(f"❌ Serviço não encontrado: {explicit_service_id}", file=sys.stderr)
            sys.exit(1)
        return service

    # Busca o último não terminal para ser útil em redispatch
    not_in = ",".join(sorted(TERMINAL_STATUSES))
    non_terminal_filters = (
        f"status=not.in.({not_in})"
        "&order=created_at.desc"
        "&limit=1"
    )
    service = _fetch_first_row_with_projection_fallback(
        supabase_url=supabase_url,
        headers=headers,
        filters_and_order=non_terminal_filters,
        projection_candidates=projection_candidates,
    )
    if service:
        return service

    # fallback: último registro absoluto
    fallback_filters = "order=created_at.desc&limit=1"
    return _fetch_first_row_with_projection_fallback(
        supabase_url=supabase_url,
        headers=headers,
        filters_and_order=fallback_filters,
        projection_candidates=projection_candidates,
    )


def redispatch_service(supabase_url: str, service_key: str, service_id: str) -> dict[str, Any]:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }
    url = f"{supabase_url}/functions/v1/dispatch"
    body = {"serviceId": service_id, "action": "start_dispatch"}
    return _request_json(url, "POST", headers, body)


def _delete_rows_by_service_id(
    supabase_url: str,
    headers: dict[str, str],
    table: str,
    service_id: str,
) -> int:
    query = urllib.parse.urlencode({"service_id": f"eq.{service_id}"})
    safe_table = quote(table, safe="")
    url = f"{supabase_url}/rest/v1/{safe_table}?{query}"
    delete_headers = dict(headers)
    delete_headers["Prefer"] = "return=representation"
    rows, err = _request_json_safe(url, "DELETE", delete_headers)
    if err is not None:
        return -1
    if isinstance(rows, list):
        return len(rows)
    return 0


def _reset_dispatch_queue_row(
    supabase_url: str,
    headers: dict[str, str],
    table: str,
    service_id: str,
) -> bool:
    query = urllib.parse.urlencode({"service_id": f"eq.{service_id}"})
    safe_table = quote(table, safe="")
    url = f"{supabase_url}/rest/v1/{safe_table}?{query}"
    body = {
        "status": "pending",
        "attempts": 0,
        "last_error": None,
        "next_run_at": "now()",
    }
    patch_headers = dict(headers)
    patch_headers["Prefer"] = "return=representation"
    _, err = _request_json_safe(url, "PATCH", patch_headers, body)
    return err is None


def force_requeue_cleanup(supabase_url: str, service_key: str, service_id: str) -> dict[str, Any]:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }
    deleted = {}
    for table in NOTIF_TABLE_CANDIDATES:
        deleted_count = _delete_rows_by_service_id(supabase_url, headers, table, service_id)
        if deleted_count >= 0:
            deleted[table] = deleted_count

    queue_reset = {}
    for table in DISPATCH_QUEUE_TABLE_CANDIDATES:
        queue_reset[table] = _reset_dispatch_queue_row(supabase_url, headers, table, service_id)

    return {
        "deleted_notification_rows": deleted,
        "queue_reset": queue_reset,
    }


def refresh_queue(supabase_url: str, service_key: str, service_id: str) -> dict[str, Any]:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
    }
    url = f"{supabase_url}/functions/v1/dispatch"
    body = {"serviceId": service_id, "action": "refresh_queue"}
    return _request_json(url, "POST", headers, body)


def reactivate_service_for_notification(
    supabase_url: str,
    service_key: str,
    service_id: str,
) -> dict[str, Any]:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation,resolution=merge-duplicates",
    }
    sid_q = urllib.parse.quote(service_id, safe="")
    now_expr = "now()"

    service_req_url = (
        f"{supabase_url}/rest/v1/service_requests"
        f"?id=eq.{sid_q}&provider_id=is.null"
    )
    service_payload = {
        "status": "searching_provider",
        "status_updated_at": now_expr,
        "updated_at": now_expr,
    }
    _, service_err = _request_json_safe(
        service_req_url,
        "PATCH",
        headers,
        service_payload,
    )

    notif_url = f"{supabase_url}/rest/v1/notificacao_de_servicos?service_id=eq.{sid_q}"
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
    _, notif_err = _request_json_safe(
        notif_url,
        "PATCH",
        headers,
        notif_payload,
    )

    queue_url = f"{supabase_url}/rest/v1/service_dispatch_queue?on_conflict=service_id"
    queue_payload = {
        "service_id": service_id,
        "status": "pending",
        "next_run_at": now_expr,
        "attempts": 0,
        "updated_at": now_expr,
    }
    _, queue_err = _request_json_safe(
        queue_url,
        "POST",
        headers,
        queue_payload,
    )

    return {
        "service_request_patch_error": service_err,
        "notificacao_patch_error": notif_err,
        "dispatch_queue_upsert_error": queue_err,
        "ok": all(e is None for e in [service_err, notif_err, queue_err]),
    }


def resend_service_notification(
    supabase_url: str,
    service_key: str,
    service_id: str,
    *,
    force_requeue: bool = False,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "service_id": service_id,
        "reactivation": reactivate_service_for_notification(
            supabase_url,
            service_key,
            service_id,
        ),
    }

    if force_requeue:
        result["cleanup"] = force_requeue_cleanup(
            supabase_url,
            service_key,
            service_id,
        )
        result["refresh_queue"] = refresh_queue(
            supabase_url,
            service_key,
            service_id,
        )

    result["dispatch"] = redispatch_service(supabase_url, service_key, service_id)
    return result


def main() -> None:
    _load_dotenv_local()

    parser = argparse.ArgumentParser(description="Busca último serviço e opcionalmente redispara notificações.")
    parser.add_argument("--service-id", help="UUID do serviço (opcional).")
    parser.add_argument("--redispatch", action="store_true", help="Se informado, dispara start_dispatch para o serviço selecionado.")
    parser.add_argument(
        "--resend-notification",
        action="store_true",
        help="Reativa service_requests/notificacao_de_servicos/fila e redispara a notificação do serviço.",
    )
    parser.add_argument(
        "--resend-last-notification",
        action="store_true",
        help="Busca automaticamente o último pedido elegível e reenvía a notificação.",
    )
    parser.add_argument(
        "--force-requeue",
        action="store_true",
        help="Força novo ciclo removendo histórico de notificação/fila do service_id antes do redispatch.",
    )
    args = parser.parse_args()

    supabase_url = _require_env("SUPABASE_URL").rstrip("/")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip() or os.getenv("SERVICE_ROLE_KEY", "").strip()
    if not service_key:
        print("❌ Defina SUPABASE_SERVICE_ROLE_KEY (ou SERVICE_ROLE_KEY).", file=sys.stderr)
        sys.exit(1)

    service = fetch_last_service(supabase_url, service_key, args.service_id)
    service_id = str(service.get("id", "")).strip()

    print("📌 Último serviço selecionado:")
    print(json.dumps(service, ensure_ascii=False, indent=2))

    if args.resend_notification or args.resend_last_notification:
        if not service_id:
            print("❌ service_id inválido para reenvio.", file=sys.stderr)
            sys.exit(1)
        if args.service_id:
            print(f"🔁 Reativando e reenviando notificações para service_id={service_id}...")
        else:
            print(f"🔁 Reativando e reenviando notificações para o último pedido elegível: service_id={service_id}...")
        response = resend_service_notification(
            supabase_url,
            service_key,
            service_id,
            force_requeue=args.force_requeue,
        )
        print("📦 Resultado do reenvio:")
        print(json.dumps(response, ensure_ascii=False, indent=2))
        return

    if not args.redispatch:
        return

    if not service_id:
        print("❌ service_id inválido para redispatch.", file=sys.stderr)
        sys.exit(1)

    if args.force_requeue:
        print("🧹 Modo forçado ativo: limpando histórico de notificação/fila...")
        cleanup = force_requeue_cleanup(supabase_url, service_key, service_id)
        print("📦 Resultado da limpeza:")
        print(json.dumps(cleanup, ensure_ascii=False, indent=2))

        print("🔁 Solicitando refresh_queue para materializar nova fila...")
        refresh_response = refresh_queue(supabase_url, service_key, service_id)
        print("📦 Resposta refresh_queue:")
        print(json.dumps(refresh_response, ensure_ascii=False, indent=2))

    print(f"🚀 Redisparando notificações para service_id={service_id}...")
    response = redispatch_service(supabase_url, service_key, service_id)
    print("📦 Resposta dispatch:")
    print(json.dumps(response, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
