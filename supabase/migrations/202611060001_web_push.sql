alter table public.os
  add column if not exists web_notificado_em timestamptz;

create table if not exists public.web_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  subscription jsonb not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists web_push_subscriptions_user_id_idx
  on public.web_push_subscriptions(user_id);

alter table public.web_push_subscriptions enable row level security;

drop policy if exists web_push_subscriptions_select_own on public.web_push_subscriptions;
create policy web_push_subscriptions_select_own
  on public.web_push_subscriptions for select
  to authenticated using (user_id = auth.uid());

drop policy if exists web_push_subscriptions_insert_own on public.web_push_subscriptions;
create policy web_push_subscriptions_insert_own
  on public.web_push_subscriptions for insert
  to authenticated with check (user_id = auth.uid());

drop policy if exists web_push_subscriptions_delete_own on public.web_push_subscriptions;
create policy web_push_subscriptions_delete_own
  on public.web_push_subscriptions for delete
  to authenticated using (user_id = auth.uid());

drop policy if exists web_push_subscriptions_update_own on public.web_push_subscriptions;
create policy web_push_subscriptions_update_own
  on public.web_push_subscriptions for update
  to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid());