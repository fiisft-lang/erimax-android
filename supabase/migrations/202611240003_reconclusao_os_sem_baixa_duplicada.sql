-- Ao reabrir e concluir novamente uma O.S., estorna a baixa anterior antes
-- de processar a lista atual, evitando descontar o mesmo material duas vezes.
create or replace function public.almox_gerar_solicitacao_ao_concluir_os()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_itens jsonb;
begin
  if new.status = 'Concluída'
     and old.status is distinct from 'Concluída' then
    v_itens := coalesce(new.materiais_utilizados,'[]'::jsonb);
    if jsonb_array_length(v_itens) = 0
       and nullif(trim(coalesce(new.peca,'')),'') is not null then
      v_itens := jsonb_build_array(jsonb_build_object(
        'nome',trim(new.peca),
        'quantidade',coalesce(new.peca_quantidade,1)
      ));
    end if;
    perform public.almox_processar_materiais_os(new.id,v_itens,true);
  end if;
  return new;
end;
$function$;
