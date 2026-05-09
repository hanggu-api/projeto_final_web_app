-- Alinhamento emergencial do schema da tabela public.service_requests
-- Objetivo: evitar falhas 42703 (coluna inexistente) em fluxos ativos de dispatch/tracking/payments.

begin;

alter table if exists public.service_requests
  add column if not exists updated_at timestamptz default now(),
  add column if not exists dispatch_started_at timestamptz,
  add column if not exists dispatch_round integer default 0,
  add column if not exists provider_uid uuid,
  add column if not exists client_uid uuid,
  add column if not exists schedule_proposed_by_user_id bigint,
  add column if not exists schedule_expires_at timestamptz,
  add column if not exists schedule_confirmed_at timestamptz,
  add column if not exists schedule_reminder_sent_at timestamptz,
  add column if not exists schedule_round integer default 0,
  add column if not exists payment_method_id text,
  add column if not exists fee_admin_rate numeric(6,4),
  add column if not exists fee_admin_amount numeric(12,2),
  add column if not exists amount_payable_on_site numeric(12,2);

-- Manter updated_at consistente automaticamente
create or replace function public.touch_service_requests_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_touch_service_requests_updated_at on public.service_requests;
create trigger trg_touch_service_requests_updated_at
before update on public.service_requests
for each row execute function public.touch_service_requests_updated_at();

-- Backfill leve
update public.service_requests
set updated_at = coalesce(updated_at, created_at, now())
where updated_at is null;

commit;
