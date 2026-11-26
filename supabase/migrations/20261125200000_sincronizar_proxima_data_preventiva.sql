-- Sincroniza a próxima data da preventiva ao concluir a O.S. e restaura
-- os valores anteriores se a mesma O.S. for reaberta.
-- Exclusiva da branch de testes até validação e aprovação.

create or replace function private.sincronizar_execucao_preventiva_os()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_data_conclusao date;
  v_ultima_anterior date;
  v_data_prevista_anterior date;
  v_execucao_id bigint;
begin
  if new.preventiva_id is null then
    return new;
  end if;

  -- Primeira conclusão (ou nova conclusão depois de uma reabertura).
  if old.status is distinct from new.status and new.status = 'Concluída' then
    -- Trava a preventiva para capturar um snapshot consistente.
    select p.ultima, p.data_prevista
      into v_ultima_anterior, v_data_prevista_anterior
      from public.preventivas p
     where p.id = new.preventiva_id
     for update;

    -- Só avança a data se houver uma execução vinculada que permita
    -- reverter a alteração caso esta O.S. seja reaberta.
    update public.preventiva_execucoes
       set status = 'concluida',
           ultima_anterior = v_ultima_anterior,
           data_prevista_anterior = v_data_prevista_anterior,
           sincronizada_em = now(),
           atualizado_em = now()
     where os_id = new.id
     returning id into v_execucao_id;

    if v_execucao_id is not null then
      v_data_conclusao := (coalesce(new.data_conclusao, now())
                           at time zone 'America/Sao_Paulo')::date;

      update public.preventivas p
         set ultima = v_data_conclusao,
             data_prevista = v_data_conclusao + coalesce(nullif(p.intervalo_dias, 0), 30)
       where p.id = new.preventiva_id;
    end if;

    if new.preventiva_atrasada then
      update public.os set preventiva_atrasada = false where id = new.id;
    end if;

  -- Reabertura ou cancelamento de uma O.S. que já havia sido concluída:
  -- restaura exatamente as datas que existiam antes daquela conclusão.
  elsif old.status = 'Concluída' and new.status is distinct from 'Concluída' then
    select e.ultima_anterior, e.data_prevista_anterior
      into v_ultima_anterior, v_data_prevista_anterior
      from public.preventiva_execucoes e
     where e.os_id = new.id
       and e.sincronizada_em is not null
     for update;

    if found then
      update public.preventivas p
         set ultima = v_ultima_anterior,
             data_prevista = v_data_prevista_anterior
       where p.id = new.preventiva_id;

      update public.preventiva_execucoes
         set status = case when new.status = 'Cancelada' then 'cancelada' else 'aberta' end,
             ultima_anterior = null,
             data_prevista_anterior = null,
             sincronizada_em = null,
             atualizado_em = now()
       where os_id = new.id;
    else
      -- Não inventa datas caso a execução não tenha snapshot histórico.
      update public.preventiva_execucoes
         set status = case when new.status = 'Cancelada' then 'cancelada' else 'aberta' end,
             atualizado_em = now()
       where os_id = new.id;
    end if;

    if new.preventiva_atrasada then
      update public.os set preventiva_atrasada = false where id = new.id;
    end if;

  elsif new.status = 'Cancelada' then
    update public.preventiva_execucoes
       set status = 'cancelada',
           atualizado_em = now()
     where os_id = new.id
       and status not in ('concluida','cancelada');

    if new.preventiva_atrasada then
      update public.os set preventiva_atrasada = false where id = new.id;
    end if;
  end if;

  return new;
end;
$$;

revoke all on function private.sincronizar_execucao_preventiva_os() from public, anon, authenticated;
grant execute on function private.sincronizar_execucao_preventiva_os() to service_role;

drop trigger if exists trg_sincronizar_execucao_preventiva_os on public.os;
create trigger trg_sincronizar_execucao_preventiva_os
after update of status on public.os
for each row
when (old.status is distinct from new.status and new.preventiva_id is not null)
execute function private.sincronizar_execucao_preventiva_os();
