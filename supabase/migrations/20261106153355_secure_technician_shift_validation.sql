create or replace function public.validar_tecnico_online_ao_assumir_os()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_turno_ativo boolean;
begin
  if new.status = 'Em Atendimento'
     and new.tecnico is not null
     and (old.status is distinct from new.status or old.tecnico is distinct from new.tecnico) then
    select p.id into v_user_id
    from public.perfis p
    where p.nome = new.tecnico and p.perfil = 'tecnico'
    limit 1;

    if v_user_id is not null then
      select s.turno_ativo into v_turno_ativo
      from public.status_tecnicos s
      where s.user_id = v_user_id;

      if not coalesce(v_turno_ativo, false) then
        raise exception 'O técnico % está OFFLINE. Ele precisa iniciar o expediente antes de assumir esta O.S.', new.tecnico;
      end if;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.validar_tecnico_online_ao_assumir_os() from public, anon, authenticated;