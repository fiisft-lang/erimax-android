-- Allow every authenticated EriMax profile to manage its own work shift.
-- Managers retain permission to manage team status records.
drop policy if exists status_tecnicos_inserir_proprio on public.status_tecnicos;
create policy status_tecnicos_inserir_proprio
  on public.status_tecnicos for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid())
        and p.perfil in ('tecnico', 'operador', 'gestor')
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
        where p.id = (select auth.uid())
          and p.perfil in ('tecnico', 'operador', 'gestor')
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
        where p.id = (select auth.uid())
          and p.perfil in ('tecnico', 'operador', 'gestor')
      )
    )
    or exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.perfil = 'gestor'
    )
  );

-- Existing accounts start offline; new accounts create their status on first shift start.
insert into public.status_tecnicos (user_id, status, turno_ativo, atualizado_em)
select p.id, 'OFFLINE', false, now()
from public.perfis p
where p.perfil in ('tecnico', 'operador', 'gestor')
on conflict (user_id) do nothing;
