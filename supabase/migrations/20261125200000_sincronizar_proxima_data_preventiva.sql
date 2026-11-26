-- Garante que a próxima data da preventiva seja atualizada na mesma transação
-- que conclui a O.S.; não depende de uma segunda gravação pelo aplicativo.
-- Exclusiva da branch de testes até validação e aprovação.

create or replace function private.sincronizar_execucao_preventiva_os()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_data_conclusao date;
begin
  if new.preventiva_id is null then
    return new;
  end if;

  if new.status = 'Concluída' then
    update public.preventiva_execucoes
       set status = 'concluida',
           atualizado_em = now()
     where os_id = new.id
       and status <> 'concluida';

    -- A data é calculada no fuso operacional do EriMax (São Paulo).
    -- A atualização ocorre dentro da mesma transação da conclusão da O.S.
    v_data_conclusao := (coalesce(new.data_conclusao, now())
                         at time zone 'America/Sao_Paulo')::date;

    update public.preventivas p
       set ultima = v_data_conclusao,
           data_prevista = v_data_conclusao + coalesce(nullif(p.intervalo_dias, 0), 30)
     where p.id = new.preventiva_id;

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
