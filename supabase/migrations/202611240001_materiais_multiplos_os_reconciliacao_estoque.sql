-- Materiais múltiplos por O.S. e reconciliação segura do estoque em edições.
alter table public.os
  add column if not exists materiais_utilizados jsonb not null default '[]'::jsonb;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'os_materiais_utilizados_array_chk'
      and conrelid = 'public.os'::regclass
  ) then
    alter table public.os
      add constraint os_materiais_utilizados_array_chk
      check (jsonb_typeof(materiais_utilizados) = 'array');
  end if;
end $$;

create or replace function public.almox_aplicar_movimentacao()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_saldo numeric(14,3);
  v_novo numeric(14,3);
  v_auto_os boolean := coalesce(current_setting('erimax.almox_auto_os', true), '') = 'on'
    and new.os_id is not null
    and (
      new.chave_idempotencia like 'os:%:consumo:%'
      or new.chave_idempotencia like 'os:%:estorno:%'
    );
begin
  if auth.uid() is null or (coalesce(public.meu_perfil(),'') <> 'gestor' and not v_auto_os) then
    raise exception 'Somente o Gestor pode movimentar o estoque manualmente.';
  end if;
  select quantidade_atual into v_saldo
  from public.almox_materiais
  where id = new.material_id and ativo = true
  for update;
  if not found then raise exception 'Material não encontrado ou inativo.'; end if;
  if new.tipo = 'entrada' then
    v_novo := v_saldo + new.quantidade;
  elsif new.tipo = 'saida' then
    if v_saldo < new.quantidade then
      raise exception 'Estoque insuficiente. Disponível: %', v_saldo;
    end if;
    v_novo := v_saldo - new.quantidade;
  else
    v_novo := new.quantidade;
  end if;
  new.saldo_anterior := v_saldo;
  new.saldo_posterior := v_novo;
  update public.almox_materiais
  set quantidade_atual = v_novo, atualizado_em = now()
  where id = new.material_id;
  return new;
end;
$function$;

create or replace function public.almox_processar_materiais_os(
  p_os_id bigint,
  p_itens jsonb,
  p_estornar boolean default false
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_item jsonb;
  v_nome text;
  v_qtd numeric(14,3);
  v_material_id uuid;
  v_saldo numeric(14,3);
  v_unidade text;
  v_idx integer := 0;
  v_mov record;
  v_chave text;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Sessão não autenticada.'; end if;
  if jsonb_typeof(coalesce(p_itens,'[]'::jsonb)) <> 'array' then
    raise exception 'A lista de materiais da O.S. é inválida.';
  end if;

  -- Primeiro desfaz, com lançamentos de entrada, todas as baixas anteriores
  -- que foram originadas por esta O.S. ou por solicitações aprovadas dela.
  if p_estornar then
    perform set_config('erimax.almox_auto_os','on',true);
    for v_mov in
      select m.*
      from public.almox_movimentacoes m
      where m.tipo = 'saida'
        and (
          (
            m.os_id = p_os_id
            and (
              m.motivo like 'Baixa automática pela conclusão da O.S.%'
              or m.motivo like 'Utilização informada na O.S.%'
            )
          )
          or m.chave_idempotencia = 'os:' || p_os_id::text || ':consumo'
          or m.chave_idempotencia like 'os:' || p_os_id::text || ':consumo:%'
        )
      order by m.criado_em, m.id
    loop
      v_chave := 'os:' || p_os_id::text || ':estorno:' || v_mov.id::text;
      if not exists (
        select 1 from public.almox_movimentacoes x
        where x.chave_idempotencia = v_chave
      ) then
        insert into public.almox_movimentacoes
          (material_id,tipo,quantidade,motivo,os_id,chave_idempotencia,criado_por)
        values
          (v_mov.material_id,'entrada',v_mov.quantidade,
           'Estorno automático da baixa anterior da O.S. #' || p_os_id::text,
           p_os_id,v_chave,v_uid);
      end if;
    end loop;
    update public.almox_solicitacoes
    set status = 'recusada',
        analisado_por = v_uid,
        analisado_em = now(),
        justificativa_analise = 'Solicitação substituída após correção dos materiais da O.S. #' || p_os_id::text
    where os_id = p_os_id
      and status in ('pendente','estoque_insuficiente','nao_cadastrado','aprovada');
  end if;

  -- Registra a lista atual, com uma movimentação/pendência independente por item.
  perform set_config('erimax.almox_auto_os','on',true);
  for v_item in
    select value from jsonb_array_elements(coalesce(p_itens,'[]'::jsonb))
  loop
    v_idx := v_idx + 1;
    v_nome := trim(coalesce(v_item->>'nome',v_item->>'material',''));
    if v_nome = '' then
      raise exception 'Informe o nome do material no item %.', v_idx;
    end if;
    if coalesce(v_item->>'quantidade','') !~ '^[0-9]+([.][0-9]+)?$' then
      raise exception 'Quantidade inválida para o material "%".', v_nome;
    end if;
    v_qtd := (v_item->>'quantidade')::numeric(14,3);
    if v_qtd <= 0 then raise exception 'A quantidade de "%" precisa ser maior que zero.', v_nome; end if;

    v_material_id := null;
    v_saldo := null;
    v_unidade := coalesce(nullif(trim(v_item->>'unidade'),''),'un');
    select m.id,m.quantidade_atual,m.unidade
      into v_material_id,v_saldo,v_unidade
    from public.almox_materiais m
    where m.ativo = true
      and (
        lower(regexp_replace(trim(m.nome),'[[:space:][:punct:]]+','','g')) =
          lower(regexp_replace(v_nome,'[[:space:][:punct:]]+','','g'))
        or lower(regexp_replace(trim(coalesce(m.codigo,'')),'[[:space:][:punct:]]+','','g')) =
          lower(regexp_replace(v_nome,'[[:space:][:punct:]]+','','g'))
      )
    order by case when lower(trim(m.nome)) = lower(v_nome) then 0 else 1 end
    limit 1
    for update;

    if v_material_id is not null and v_saldo >= v_qtd then
      insert into public.almox_movimentacoes
        (material_id,tipo,quantidade,motivo,os_id,chave_idempotencia,criado_por)
      values
        (v_material_id,'saida',v_qtd,
         'Baixa automática pela conclusão da O.S. #' || p_os_id::text || ' — item ' || v_idx::text,
         p_os_id,'os:' || p_os_id::text || ':consumo:' || gen_random_uuid()::text,v_uid);
    else
      insert into public.almox_solicitacoes
        (os_id,nome_material,quantidade,unidade,material_id,observacao,status,criado_por,chave_idempotencia)
      values
        (p_os_id,v_nome,v_qtd,coalesce(v_unidade,'un'),v_material_id,
         case when v_material_id is null
           then 'Material informado na O.S. e ainda não cadastrado no Almoxarifado.'
           else 'Estoque insuficiente no momento da conclusão. Repor e aprovar a saída.'
         end,
         case when v_material_id is null then 'nao_cadastrado' else 'estoque_insuficiente' end,
         v_uid,'os:' || p_os_id::text || ':solicitacao:' || gen_random_uuid()::text);
    end if;
  end loop;
  perform set_config('erimax.almox_auto_os','off',true);
end;
$function$;

revoke all on function public.almox_processar_materiais_os(bigint,jsonb,boolean) from public, anon, authenticated;

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
    perform public.almox_processar_materiais_os(new.id,v_itens,false);
  end if;
  return new;
end;
$function$;

create or replace function public.almox_reconciliar_materiais_os_editados()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_itens jsonb;
begin
  if new.status = 'Concluída'
     and old.status = 'Concluída'
     and (
       old.peca is distinct from new.peca
       or old.peca_quantidade is distinct from new.peca_quantidade
       or old.materiais_utilizados is distinct from new.materiais_utilizados
     ) then
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

drop trigger if exists trg_almox_reconciliar_materiais_os_editados on public.os;
create trigger trg_almox_reconciliar_materiais_os_editados
after update of peca, peca_quantidade, materiais_utilizados on public.os
for each row execute function public.almox_reconciliar_materiais_os_editados();

create or replace function public.erimax_editar_os_completa(
  p_os_id bigint,
  p_dados jsonb,
  p_motivo text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_perfil text;
  v_nome text;
  v_antigo jsonb;
  v_materiais jsonb;
  v_peca text;
  v_qtd numeric;
begin
  if (select auth.uid()) is null then raise exception 'Sessão não autenticada.'; end if;
  select p.perfil,p.nome into v_perfil,v_nome
  from public.perfis p where p.id=(select auth.uid());
  if v_perfil is distinct from 'gestor' then raise exception 'Somente o gestor pode editar todos os dados da O.S.'; end if;
  if length(trim(coalesce(p_motivo,'')))<8 then raise exception 'Informe uma justificativa com pelo menos 8 caracteres.'; end if;
  if jsonb_typeof(p_dados) is distinct from 'object' then raise exception 'Dados da O.S. inválidos.'; end if;
  select to_jsonb(o) into v_antigo from public.os o where o.id=p_os_id for update;
  if v_antigo is null then raise exception 'O.S. não encontrada.'; end if;
  if coalesce(p_dados->>'maquina','')='' or coalesce(p_dados->>'setor','')='' or coalesce(p_dados->>'turno','')='' then raise exception 'Máquina, setor e turno são obrigatórios.'; end if;
  if coalesce(p_dados->>'situacao_equipamento','') not in ('Rodando','Parado') then raise exception 'Selecione se a máquina estava Rodando ou Parada.'; end if;
  if coalesce(p_dados->>'prioridade','') not in ('Baixa','Média','Alta','Urgente','Crítica','Critica') then raise exception 'Prioridade inválida.'; end if;
  if coalesce(p_dados->>'tipo','')='' or coalesce(p_dados->>'descricao','')='' then raise exception 'Tipo e descrição são obrigatórios.'; end if;
  if nullif(p_dados->>'created_at','') is null then raise exception 'Informe a data de abertura.'; end if;
  if nullif(p_dados->>'data_atendimento','') is not null and (p_dados->>'data_atendimento')::timestamptz < (p_dados->>'created_at')::timestamptz then raise exception 'Atendimento não pode ser anterior à abertura.'; end if;
  if nullif(p_dados->>'data_conclusao','') is not null and (p_dados->>'data_atendimento') is null then raise exception 'Informe o início do atendimento antes da conclusão.'; end if;
  if nullif(p_dados->>'data_conclusao','') is not null and (p_dados->>'data_conclusao')::timestamptz < (p_dados->>'data_atendimento')::timestamptz then raise exception 'Conclusão não pode ser anterior ao atendimento.'; end if;

  if p_dados ? 'materiais_utilizados' then
    v_materiais := coalesce(p_dados->'materiais_utilizados','[]'::jsonb);
    if jsonb_typeof(v_materiais) is distinct from 'array' then raise exception 'Lista de materiais inválida.'; end if;
    v_peca := nullif(trim(coalesce(v_materiais->0->>'nome','')),'');
    v_qtd := coalesce(nullif(v_materiais->0->>'quantidade','')::numeric,1);
  else
    v_materiais := coalesce(v_antigo->'materiais_utilizados','[]'::jsonb);
    v_peca := nullif(p_dados->>'peca','');
    v_qtd := coalesce(nullif(p_dados->>'peca_quantidade','')::numeric,(v_antigo->>'peca_quantidade')::numeric,1);
  end if;

  update public.os set
    maquina=p_dados->>'maquina', setor=p_dados->>'setor', turno=p_dados->>'turno',
    tipo=p_dados->>'tipo', prioridade=p_dados->>'prioridade', descricao=p_dados->>'descricao',
    tecnico=nullif(p_dados->>'tecnico',''), situacao_equipamento=p_dados->>'situacao_equipamento',
    causa=nullif(p_dados->>'causa',''), peca=v_peca, peca_quantidade=v_qtd,
    materiais_utilizados=v_materiais,
    servico_executado=nullif(p_dados->>'servico_executado',''),
    created_at=(p_dados->>'created_at')::timestamptz,
    data_atendimento=nullif(p_dados->>'data_atendimento','')::timestamptz,
    data_conclusao=nullif(p_dados->>'data_conclusao','')::timestamptz,
    rodando_em=nullif(p_dados->>'rodando_em','')::timestamptz,
    observacao_rodando=nullif(p_dados->>'observacao_rodando',''),
    ajustado_por=v_nome, ajustado_em=now(), ajuste_obs=trim(p_motivo)
  where id=p_os_id;
end
$function$;
