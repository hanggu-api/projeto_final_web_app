-- ============================================================
-- FASE 2: Backend-First Remote UI
-- Tabelas para definição, variantes, publicação e políticas
-- de telas remotas, além de app_configs centralizado.
-- ============================================================

-- ------------------------------------------------------------
-- 1. app_configs
-- ------------------------------------------------------------
create table if not exists public.app_configs (
  id            bigserial primary key,
  key           text        not null,
  value         text        not null,
  category      text        not null default 'general',
  platform_scope text       not null default 'all',
  is_active     boolean     not null default true,
  revision      text        not null default '1',
  description   text,
  created_at    timestamptz not null default timezone('utc', now()),
  updated_at    timestamptz not null default timezone('utc', now()),
  constraint app_configs_key_platform_uq unique (key, platform_scope)
);

create index if not exists app_configs_key_idx on public.app_configs (key);
create index if not exists app_configs_category_idx on public.app_configs (category);

alter table public.app_configs enable row level security;

drop policy if exists "app_configs_select_authenticated" on public.app_configs;
create policy "app_configs_select_authenticated"
on public.app_configs for select to authenticated
using (is_active = true);

drop policy if exists "app_configs_select_anon" on public.app_configs;
create policy "app_configs_select_anon"
on public.app_configs for select to anon
using (is_active = true);

-- ------------------------------------------------------------
-- 2. remote_screen_definitions
-- ------------------------------------------------------------
create table if not exists public.remote_screen_definitions (
  id            bigserial   primary key,
  screen_key    text        not null unique,
  description   text,
  schema_version int        not null default 1,
  role_scope    text        not null default 'all',
  platform_scope text       not null default 'all',
  is_active     boolean     not null default true,
  created_at    timestamptz not null default timezone('utc', now()),
  updated_at    timestamptz not null default timezone('utc', now())
);

create index if not exists remote_screen_definitions_key_idx
  on public.remote_screen_definitions (screen_key);

alter table public.remote_screen_definitions enable row level security;

drop policy if exists "remote_screen_definitions_select" on public.remote_screen_definitions;
create policy "remote_screen_definitions_select"
on public.remote_screen_definitions for select to authenticated
using (is_active = true);

-- ------------------------------------------------------------
-- 3. remote_screen_variants
-- ------------------------------------------------------------
create table if not exists public.remote_screen_variants (
  id              bigserial   primary key,
  screen_key      text        not null references public.remote_screen_definitions(screen_key) on delete cascade,
  variant_key     text        not null,
  role_scope      text        not null default 'all',
  platform_scope  text        not null default 'all',
  status_scope    text        not null default 'all',
  context_scope   jsonb       not null default '{}',
  layout_json     jsonb       not null default '{}',
  meta_json       jsonb       not null default '{}',
  commands_used   text[]      not null default '{}',
  schema_version  int         not null default 1,
  is_active       boolean     not null default true,
  priority        int         not null default 0,
  created_at      timestamptz not null default timezone('utc', now()),
  updated_at      timestamptz not null default timezone('utc', now()),
  constraint remote_screen_variants_uq unique (screen_key, variant_key, role_scope, platform_scope)
);

create index if not exists remote_screen_variants_screen_key_idx
  on public.remote_screen_variants (screen_key);
create index if not exists remote_screen_variants_role_platform_idx
  on public.remote_screen_variants (role_scope, platform_scope);

alter table public.remote_screen_variants enable row level security;

drop policy if exists "remote_screen_variants_select" on public.remote_screen_variants;
create policy "remote_screen_variants_select"
on public.remote_screen_variants for select to authenticated
using (is_active = true);

-- ------------------------------------------------------------
-- 4. remote_screen_publications
-- ------------------------------------------------------------
create table if not exists public.remote_screen_publications (
  id              bigserial   primary key,
  screen_key      text        not null references public.remote_screen_definitions(screen_key) on delete cascade,
  variant_id      bigint      references public.remote_screen_variants(id) on delete set null,
  revision        text        not null,
  is_active       boolean     not null default false,
  published_by    uuid        references auth.users(id) on delete set null,
  published_at    timestamptz,
  rollback_of     bigint      references public.remote_screen_publications(id) on delete set null,
  change_summary  text,
  full_schema     jsonb       not null default '{}',
  created_at      timestamptz not null default timezone('utc', now()),
  updated_at      timestamptz not null default timezone('utc', now())
);

create index if not exists remote_screen_publications_screen_key_idx
  on public.remote_screen_publications (screen_key);
create index if not exists remote_screen_publications_active_idx
  on public.remote_screen_publications (screen_key, is_active)
  where is_active = true;

alter table public.remote_screen_publications enable row level security;

drop policy if exists "remote_screen_publications_select" on public.remote_screen_publications;
create policy "remote_screen_publications_select"
on public.remote_screen_publications for select to authenticated
using (is_active = true);

-- ------------------------------------------------------------
-- 5. remote_action_policies
-- ------------------------------------------------------------
create table if not exists public.remote_action_policies (
  id              bigserial   primary key,
  screen_key      text        not null references public.remote_screen_definitions(screen_key) on delete cascade,
  command_key     text        not null,
  role_scope      text        not null default 'all',
  platform_scope  text        not null default 'all',
  is_allowed      boolean     not null default true,
  requires_auth   boolean     not null default true,
  rate_limit_rpm  int,
  description     text,
  created_at      timestamptz not null default timezone('utc', now()),
  updated_at      timestamptz not null default timezone('utc', now()),
  constraint remote_action_policies_uq unique (screen_key, command_key, role_scope, platform_scope)
);

create index if not exists remote_action_policies_screen_key_idx
  on public.remote_action_policies (screen_key);
create index if not exists remote_action_policies_command_key_idx
  on public.remote_action_policies (command_key);

alter table public.remote_action_policies enable row level security;

drop policy if exists "remote_action_policies_select" on public.remote_action_policies;
create policy "remote_action_policies_select"
on public.remote_action_policies for select to authenticated
using (is_allowed = true);

-- ------------------------------------------------------------
-- 6. remote_content_blocks
-- ------------------------------------------------------------
create table if not exists public.remote_content_blocks (
  id              bigserial   primary key,
  block_key       text        not null unique,
  block_type      text        not null default 'generic',
  content_json    jsonb       not null default '{}',
  role_scope      text        not null default 'all',
  platform_scope  text        not null default 'all',
  is_active       boolean     not null default true,
  revision        text        not null default '1',
  description     text,
  created_at      timestamptz not null default timezone('utc', now()),
  updated_at      timestamptz not null default timezone('utc', now())
);

create index if not exists remote_content_blocks_key_idx
  on public.remote_content_blocks (block_key);
create index if not exists remote_content_blocks_type_idx
  on public.remote_content_blocks (block_type);

alter table public.remote_content_blocks enable row level security;

drop policy if exists "remote_content_blocks_select" on public.remote_content_blocks;
create policy "remote_content_blocks_select"
on public.remote_content_blocks for select to authenticated
using (is_active = true);

-- ------------------------------------------------------------
-- 7. remote_ui_audit_log
-- ------------------------------------------------------------
create table if not exists public.remote_ui_audit_log (
  id              bigserial   primary key,
  user_uid        uuid        references auth.users(id) on delete set null,
  screen_key      text        not null,
  command_key     text        not null,
  component_id    text,
  revision        text,
  store_version   text,
  patch_version   text,
  platform        text,
  role            text,
  arguments       jsonb       not null default '{}',
  entity_ids      jsonb       not null default '{}',
  result_success  boolean,
  result_message  text,
  created_at      timestamptz not null default timezone('utc', now())
);

create index if not exists remote_ui_audit_log_user_uid_idx
  on public.remote_ui_audit_log (user_uid);
create index if not exists remote_ui_audit_log_screen_command_idx
  on public.remote_ui_audit_log (screen_key, command_key);
create index if not exists remote_ui_audit_log_created_at_idx
  on public.remote_ui_audit_log (created_at desc);

alter table public.remote_ui_audit_log enable row level security;

drop policy if exists "remote_ui_audit_log_insert_own" on public.remote_ui_audit_log;
create policy "remote_ui_audit_log_insert_own"
on public.remote_ui_audit_log for insert to authenticated
with check (user_uid = auth.uid());

drop policy if exists "remote_ui_audit_log_select_own" on public.remote_ui_audit_log;
create policy "remote_ui_audit_log_select_own"
on public.remote_ui_audit_log for select to authenticated
using (user_uid = auth.uid());

-- ------------------------------------------------------------
-- 8. Dados iniciais — app_configs
-- ------------------------------------------------------------
insert into public.app_configs (key, value, category, platform_scope, description)
values
  ('flag.remote_ui.enabled',                'true',  'remote_ui', 'all', 'Liga/desliga toda a Remote UI'),
  ('flag.remote_ui.help.enabled',           'true',  'remote_ui', 'all', 'Remote UI para tela de ajuda'),
  ('flag.remote_ui.home_explore.enabled',   'true',  'remote_ui', 'all', 'Remote UI para home explore'),
  ('flag.remote_ui.driver_home.enabled',    'true',  'remote_ui', 'all', 'Remote UI para home do prestador'),
  ('flag.remote_ui.provider_search.enabled','true',  'remote_ui', 'all', 'Remote UI para busca de prestador'),
  ('flag.remote_ui.service_payment.enabled','true',  'remote_ui', 'all', 'Remote UI para pagamento'),
  ('kill_switch.remote_ui.global',          'false', 'remote_ui', 'all', 'Kill switch global da Remote UI'),
  ('kill_switch.remote_ui.help',            'false', 'remote_ui', 'all', 'Kill switch da tela de ajuda'),
  ('kill_switch.remote_ui.home_explore',    'false', 'remote_ui', 'all', 'Kill switch do home explore'),
  ('kill_switch.remote_ui.driver_home',     'false', 'remote_ui', 'all', 'Kill switch do home do prestador'),
  ('kill_switch.remote_ui.provider_search', 'false', 'remote_ui', 'all', 'Kill switch da busca de prestador'),
  ('kill_switch.remote_ui.service_payment', 'false', 'remote_ui', 'all', 'Kill switch do pagamento'),
  ('search_radius_km',                      '50',    'search',    'all', 'Raio de busca em km'),
  ('enable_packages',                       'false', 'features',  'all', 'Habilita pacotes de serviço'),
  ('enable_reserve',                        'false', 'features',  'all', 'Habilita reserva antecipada')
on conflict (key, platform_scope) do nothing;

-- ------------------------------------------------------------
-- 9. Dados iniciais — definições de telas remotas
-- ------------------------------------------------------------
insert into public.remote_screen_definitions (screen_key, description, role_scope)
values
  ('help',             'Tela de ajuda e suporte',              'all'),
  ('home_explore',     'Tela de exploração da home',           'client'),
  ('driver_home',      'Home do prestador/motorista',          'provider'),
  ('provider_search',  'Busca de prestador pelo cliente',      'client'),
  ('service_payment',  'Tela de pagamento do serviço',         'client'),
  ('service_tracking', 'Tracking operacional do serviço',      'all'),
  ('service_form',     'Formulário de solicitação de serviço', 'client')
on conflict (screen_key) do nothing;
