create or replace function public.validar_tecnico_online_ao_assumir_os()
returns trigger
language plpgsql
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

create or replace function public.sincronizar_status_tecnico_apos_os()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_nome text;
  v_user_id uuid;
  v_turno_ativo boolean;
  v_os_id bigint;
  v_status text;
begin
  for v_nome in
    select distinct nome
    from unnest(array[old.tecnico, new.tecnico]) as nomes(nome)
    where nome is not null and btrim(nome) <> ''
  loop
    select p.id into v_user_id
    from public.perfis p
    where p.nome = v_nome and p.perfil = 'tecnico'
    limit 1;

    if v_user_id is null then
      continue;
    end if;

    select s.turno_ativo into v_turno_ativo
    from public.status_tecnicos s
    where s.user_id = v_user_id;

    if not found then
      continue;
    end if;

    select o.id into v_os_id
    from public.os o
    where o.tecnico = v_nome and o.status = 'Em Atendimento'
    order by o.id desc
    limit 1;

    if v_os_id is not null then
      v_status := 'EM SERVIÇO';
    elsif coalesce(v_turno_ativo, false) then
      v_status := 'ONLINE';
    else
      v_status := 'OFFLINE';
    end if;

    update public.status_tecnicos
    set status = v_status,
        os_atual_id = v_os_id,
        atualizado_em = now()
    where user_id = v_user_id;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_validar_tecnico_online_ao_assumir_os on public.os;
create trigger trg_validar_tecnico_online_ao_assumir_os
before update of status, tecnico on public.os
for each row
execute function public.validar_tecnico_online_ao_assumir_os();

drop trigger if exists trg_sincronizar_status_tecnico_apos_os on public.os;
create trigger trg_sincronizar_status_tecnico_apos_os
after update of status, tecnico on public.os
for each row
execute function public.sincronizar_status_tecnico_apos_os();

revoke all on function public.sincronizar_status_tecnico_apos_os() from public, anon, authenticated;
revoke all on function public.validar_tecnico_online_ao_assumir_os() from public, anon, authenticated;