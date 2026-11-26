-- Sincroniza a próxima data da preventiva ao concluir a O.S. e restaura
-- os valores anteriores somente se nenhum ciclo posterior os tiver substituído.
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
  v_ultima_aplicada date;
  v_data_prevista_aplicada date;
  v_intervalo_dias integer;
  v_execucao_id bigint;
begin
  if new.preventiva_id is null then
    return new;
  end if;

  -- A preventiva é sempre bloqueada antes da execução. Assim, conclusões e
  -- reaberturas da mesma preventiva seguem a mesma ordem de bloqueio.
  if old.status is distinct from new.status and new.status = 'Concluída' then
    select p.ultima,
           p.data_prevista,
           coalesce(nullif(p.intervalo_dias, 0), 30)
      into v_ultima_anterior,
           v_data_prevista_anterior,
           v_intervalo_dias
      from public.preventivas p
     where p.id = new.preventiva_id
     for update;

    if found then
      update public.preventiva_execucoes
         set status = 'concluida',
             ultima_anterior = v_ultima_anterior,
             data_prevista_anterior = v_data_prevista_anterior,
             sincronizada_em = now(),
             atualizado_em = now()
       where os_id = new.id
       returning id into v_execucao_id;

      -- Sem execução rastreável, não altera as datas da preventiva.
      if v_execucao_id is not null then
        v_data_conclusao := (coalesce(new.data_conclusao, now())
                             at time zone 'America/Sao_Paulo')::date;
        v_ultima_aplicada := v_data_conclusao;
        v_data_prevista_aplicada := v_data_conclusao + v_intervalo_dias;

        update public.preventivas p
           set ultima = v_ultima_aplicada,
               data_prevista = v_data_prevista_aplicada
         where p.id = new.preventiva_id;

        update public.preventiva_execucoes
           set ultima_aplicada = v_ultima_aplicada,
               data_prevista_aplicada = v_data_prevista_aplicada
         where id = v_execucao_id;
      end if;
    end if;

    if new.preventiva_atrasada then
      update public.os set preventiva_atrasada = false where id = new.id;
    end if;

  -- Ao reabrir/cancelar, só restaura o snapshot se a preventiva ainda estiver
  -- exatamente no estado aplicado por esta O.S. Uma conclusão posterior muda
  -- esses valores e, portanto, nunca será sobrescrita por uma O.S. antiga.
  elsif old.status = 'Concluída' and new.status is distinct from 'Concluída' then
    perform 1
      from public.preventivas p
     where p.id = new.preventiva_id
     for update;

    select e.ultima_anterior,
           e.data_prevista_anterior,
           e.ultima_aplicada,
           e.data_prevista_aplicada
      into v_ultima_anterior,
           v_data_prevista_anterior,
           v_ultima_aplicada,
           v_data_prevista_aplicada
      from public.preventiva_execucoes e
     where e.os_id = new.id
       and e.sincronizada_em is not null
     for update;

    if found then
      update public.preventivas p
         set ultima = v_ultima_anterior,
             data_prevista = v_data_prevista_anterior
       where p.id = new.preventiva_id
         and p.ultima is not distinct from v_ultima_aplicada
         and p.data_prevista is not distinct from v_data_prevista_aplicada;

      -- Mesmo quando um ciclo posterior impede a restauração, encerra o
      -- snapshot desta O.S. para que uma reabertura futura não o reutilize.
      update public.preventiva_execucoes
         set status = case when new.status = 'Cancelada' then 'cancelada' else 'aberta' end,
             ultima_anterior = null,
             data_prevista_anterior = null,
             ultima_aplicada = null,
             data_prevista_aplicada = null,
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
