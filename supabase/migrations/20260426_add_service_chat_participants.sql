create table if not exists public.service_chat_participants (
  id uuid primary key default gen_random_uuid(),
  service_id text not null,
  role text not null,
  user_id bigint,
  display_name text,
  avatar_url text,
  phone text,
  can_send boolean not null default true,
  is_primary_operational_contact boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists service_chat_participants_service_id_idx
  on public.service_chat_participants (service_id);

create index if not exists service_chat_participants_user_id_idx
  on public.service_chat_participants (user_id);

alter table public.service_chat_participants enable row level security;

drop policy if exists "service_chat_participants_select_related" on public.service_chat_participants;
create policy "service_chat_participants_select_related"
on public.service_chat_participants
for select
to authenticated
using (
  exists (
    select 1
    from public.service_requests_new s
    where s.id::text = service_chat_participants.service_id
      and (
        s.client_uid = auth.uid()
        or s.provider_uid = auth.uid()
      )
  )
  or exists (
    select 1
    from public.agendamento_servico a
    where a.id::text = service_chat_participants.service_id
      and (
        a.cliente_uid = auth.uid()
        or a.prestador_uid = auth.uid()
      )
  )
);

drop policy if exists "service_chat_participants_upsert_related" on public.service_chat_participants;
create policy "service_chat_participants_upsert_related"
on public.service_chat_participants
for all
to authenticated
using (
  exists (
    select 1
    from public.service_requests_new s
    where s.id::text = service_chat_participants.service_id
      and (
        s.client_uid = auth.uid()
        or s.provider_uid = auth.uid()
      )
  )
  or exists (
    select 1
    from public.agendamento_servico a
    where a.id::text = service_chat_participants.service_id
      and (
        a.cliente_uid = auth.uid()
        or a.prestador_uid = auth.uid()
      )
  )
)
with check (
  exists (
    select 1
    from public.service_requests_new s
    where s.id::text = service_chat_participants.service_id
      and (
        s.client_uid = auth.uid()
        or s.provider_uid = auth.uid()
      )
  )
  or exists (
    select 1
    from public.agendamento_servico a
    where a.id::text = service_chat_participants.service_id
      and (
        a.cliente_uid = auth.uid()
        or a.prestador_uid = auth.uid()
      )
  )
);
