alter table public.status_tecnicos
  add constraint status_tecnicos_status_turno_consistente
  check (
    (turno_ativo = true and status in ('ONLINE', 'EM SERVIÇO'))
    or
    (turno_ativo = false and status = 'OFFLINE')
  );

create or replace function public.validar_encerramento_turno_tecnico()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text;
begin
  if old.turno_ativo = true and new.turno_ativo = false then
    select p.nome into v_nome
    from public.perfis p
    where p.id = new.user_id and p.perfil = 'tecnico'
    limit 1;

    if v_nome is not null and exists (
      select 1 from public.os o
      where o.tecnico = v_nome and o.status = 'Em Atendimento'
    ) then
      raise exception 'Conclua ou transfira a O.S. em serviço antes de encerrar o turno.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_validar_encerramento_turno_tecnico on public.status_tecnicos;
create trigger trg_validar_encerramento_turno_tecnico
before update of turno_ativo on public.status_tecnicos
for each row
execute function public.validar_encerramento_turno_tecnico();

revoke all on function public.validar_encerramento_turno_tecnico() from public, anon, authenticated;