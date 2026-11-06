create table if not exists public.status_tecnicos (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null default 'OFFLINE'
    check (status in ('ONLINE', 'EM SERVIÇO', 'OFFLINE')),
  turno_ativo boolean not null default false,
  turno_inicio timestamptz,
  turno_fim timestamptz,
  os_atual_id bigint references public.os(id) on delete set null,
  atualizado_em timestamptz not null default now()
);

create index if not exists status_tecnicos_status_turno_idx
  on public.status_tecnicos (status, turno_ativo);

alter table public.status_tecnicos enable row level security;
grant select, insert, update on public.status_tecnicos to authenticated;

drop policy if exists status_tecnicos_ler_autenticados on public.status_tecnicos;
create policy status_tecnicos_ler_autenticados
  on public.status_tecnicos for select to authenticated
  using (true);

drop policy if exists status_tecnicos_inserir_proprio on public.status_tecnicos;
create policy status_tecnicos_inserir_proprio
  on public.status_tecnicos for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.perfil = 'tecnico'
    )
  );

drop policy if exists status_tecnicos_atualizar_proprio_ou_gestor on public.status_tecnicos;
create policy status_tecnicos_atualizar_proprio_ou_gestor
  on public.status_tecnicos for update to authenticated
  using (
    (
      user_id = (select auth.uid())
      and exists (
        select 1 from public.perfis p
        where p.id = (select auth.uid()) and p.perfil = 'tecnico'
      )
    )
    or exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.perfil = 'gestor'
    )
  )
  with check (
    (
      user_id = (select auth.uid())
      and exists (
        select 1 from public.perfis p
        where p.id = (select auth.uid()) and p.perfil = 'tecnico'
      )
    )
    or exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.perfil = 'gestor'
    )
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'status_tecnicos'
  ) then
    alter publication supabase_realtime add table public.status_tecnicos;
  end if;
end
$$;