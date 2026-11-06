-- Etapa 9: notificação push. Rode no SQL Editor depois do schema8.sql

alter table os add column if not exists notificado_em timestamptz;

create table if not exists dispositivos(
  token text primary key,
  user_id uuid not null references auth.users on delete cascade,
  atualizado_em timestamptz not null default now()
);
alter table dispositivos enable row level security;   -- sem policies: só as funções abaixo e o servidor acessam

create or replace function public.registrar_dispositivo(p_token text) returns void
language sql security definer set search_path = public as $$
  insert into dispositivos(token, user_id, atualizado_em) values (p_token, auth.uid(), now())
  on conflict (token) do update set user_id = auth.uid(), atualizado_em = now() $$;

create or replace function public.desregistrar_dispositivo(p_token text) returns void
language sql security definer set search_path = public as $$
  delete from dispositivos where token = p_token and user_id = auth.uid() $$;
