create table if not exists public.client_locations (
  service_id uuid primary key references public.agendamento_servico(id) on delete cascade,
  client_user_id bigint,
  client_uid uuid,
  latitude double precision not null,
  longitude double precision not null,
  tracking_status text not null default 'tracking_active',
  source text not null default 'client_tracking',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists client_locations_client_uid_idx
  on public.client_locations (client_uid);

create index if not exists client_locations_updated_at_idx
  on public.client_locations (updated_at desc);

alter table public.client_locations enable row level security;

drop policy if exists "client_locations_select_participants" on public.client_locations;
create policy "client_locations_select_participants"
on public.client_locations
for select
to authenticated
using (
  exists (
    select 1
    from public.agendamento_servico s
    where s.id = client_locations.service_id
      and (s.cliente_uid = auth.uid() or s.prestador_uid = auth.uid())
  )
);

drop policy if exists "client_locations_insert_owner" on public.client_locations;
create policy "client_locations_insert_owner"
on public.client_locations
for insert
to authenticated
with check (
  client_uid = auth.uid()
  and exists (
    select 1
    from public.agendamento_servico s
    where s.id = client_locations.service_id
      and s.cliente_uid = auth.uid()
  )
);

drop policy if exists "client_locations_update_owner" on public.client_locations;
create policy "client_locations_update_owner"
on public.client_locations
for update
to authenticated
using (
  client_uid = auth.uid()
  and exists (
    select 1
    from public.agendamento_servico s
    where s.id = client_locations.service_id
      and s.cliente_uid = auth.uid()
  )
)
with check (
  client_uid = auth.uid()
);

alter table public.agendamento_servico
  add column if not exists client_tracking_active boolean not null default false,
  add column if not exists client_tracking_status text,
  add column if not exists client_tracking_source text,
  add column if not exists client_tracking_updated_at timestamptz;
