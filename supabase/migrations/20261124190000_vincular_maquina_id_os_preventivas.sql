-- Identidade imutável das máquinas em O.S., preventivas e métricas.
-- O backfill só vincula correspondências únicas; registros ambíguos permanecem sem ID.

alter table public.os
  add column if not exists maquina_id bigint;

alter table public.preventivas
  add column if not exists maquinas_ids bigint[] not null default '{}'::bigint[];

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='maquinas_prefixo_obrigatorio_check'
      and conrelid='public.maquinas'::regclass
  ) then
    alter table public.maquinas
      add constraint maquinas_prefixo_obrigatorio_check
      check (nullif(btrim(prefixo),'') is not null);
  end if;
end $$;

-- O código normalizado é único globalmente, mesmo se alguém variar hífen ou caixa.
create unique index if not exists maquinas_prefixo_normalizado_uidx
  on public.maquinas ((regexp_replace(upper(btrim(prefixo)), '[^A-Z0-9]', '', 'g')));

with correspondencias as (
  select o.id as os_id, min(m.id) as maquina_id
  from public.os o
  join public.maquinas m
    on lower(btrim(m.nome))=lower(btrim(o.maquina))
   and lower(btrim(m.setor))=lower(btrim(o.setor))
  where o.maquina_id is null
  group by o.id
  having count(m.id)=1
)
update public.os o
set maquina_id=c.maquina_id
from correspondencias c
where c.os_id=o.id;

-- Preventivas só recebem IDs se TODAS as máquinas do registro forem inequívocas.
-- Se uma delas for ambígua, a lista inteira continua legada para não omitir máquinas.
with nomes as (
  select p.id as preventiva_id,
         lower(btrim(p.setor)) as setor,
         lower(btrim(n.nome)) as nome
  from public.preventivas p
  cross join lateral jsonb_array_elements_text(
    case
      when jsonb_typeof(p.maquinas)='array' and jsonb_array_length(p.maquinas)>0
        then p.maquinas
      else jsonb_build_array(p.maquina)
    end
  ) with ordinality as n(nome,ordem)
  where cardinality(coalesce(p.maquinas_ids,'{}'::bigint[]))=0
), resolvidas as (
  select n.preventiva_id,n.nome,n.ordem,count(m.id) as correspondencias,min(m.id) as maquina_id
  from nomes n
  left join public.maquinas m
    on lower(btrim(m.setor))=n.setor
   and lower(btrim(m.nome))=n.nome
  group by n.preventiva_id,n.nome,n.ordem
), completas as (
  select r.preventiva_id,array_agg(r.maquina_id order by r.ordem) as ids
  from resolvidas r
  group by r.preventiva_id
  having bool_and(r.correspondencias=1)
     and count(*)=(select count(*) from nomes n where n.preventiva_id=r.preventiva_id)
)
update public.preventivas p
set maquinas_ids=c.ids
from completas c
where c.preventiva_id=p.id;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='os_maquina_id_fkey'
      and conrelid='public.os'::regclass
  ) then
    alter table public.os
      add constraint os_maquina_id_fkey
      foreign key (maquina_id) references public.maquinas(id)
      on delete restrict;
  end if;
end $$;

create index if not exists os_maquina_id_idx
  on public.os(maquina_id);

create index if not exists preventivas_maquinas_ids_gin_idx
  on public.preventivas using gin(maquinas_ids);

-- Para clientes antigos: completa o ID apenas quando nome + setor apontam para uma máquina.
-- Nomes duplicados permanecem sem atribuição automática.
create or replace function public.erimax_validar_os_maquina_id()
returns trigger
language plpgsql
set search_path=''
as $$
declare
  v_quantidade integer;
  v_maquina_id bigint;
begin
  if new.maquina_id is null then
    select count(*),min(m.id)
      into v_quantidade,v_maquina_id
    from public.maquinas m
    where lower(btrim(m.setor))=lower(btrim(new.setor))
      and lower(btrim(m.nome))=lower(btrim(new.maquina));

    if v_quantidade=1 then
      new.maquina_id:=v_maquina_id;
    end if;
  elsif not exists (
    select 1 from public.maquinas m
    where m.id=new.maquina_id
      and lower(btrim(m.setor))=lower(btrim(new.setor))
      and lower(btrim(m.nome))=lower(btrim(new.maquina))
  ) then
    raise exception 'O ID da máquina não corresponde ao nome e setor selecionados.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_erimax_validar_os_maquina_id on public.os;
create trigger trg_erimax_validar_os_maquina_id
before insert or update of maquina_id,maquina,setor
on public.os
for each row execute function public.erimax_validar_os_maquina_id();

create or replace function public.erimax_validar_preventiva_maquinas_ids()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  new.maquinas_ids:=coalesce(new.maquinas_ids,'{}'::bigint[]);

  if (select count(*) from unnest(new.maquinas_ids)) <>
     (select count(distinct x) from unnest(new.maquinas_ids) as ids(x)) then
    raise exception 'A preventiva contém máquina repetida.';
  end if;

  if cardinality(new.maquinas_ids)>0 then
    if jsonb_typeof(new.maquinas) is distinct from 'array'
       or jsonb_array_length(new.maquinas)<>cardinality(new.maquinas_ids) then
      raise exception 'A lista de máquinas e seus identificadores não corresponde.';
    end if;

    if exists (
      select 1
      from unnest(new.maquinas_ids) with ordinality as ids(id,ordem)
      left join jsonb_array_elements_text(new.maquinas) with ordinality as n(nome,ordem)
        using (ordem)
      left join public.maquinas m on m.id=ids.id
      where n.nome is null
         or m.id is null
         or lower(btrim(m.setor))<>lower(btrim(new.setor))
         or lower(btrim(m.nome))<>lower(btrim(n.nome))
    ) then
      raise exception 'Cada máquina deve corresponder ao seu identificador e à mesma posição da lista.';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_erimax_validar_preventiva_maquinas_ids on public.preventivas;
create trigger trg_erimax_validar_preventiva_maquinas_ids
before insert or update of maquinas_ids,setor,maquinas
on public.preventivas
for each row execute function public.erimax_validar_preventiva_maquinas_ids();

-- Protege o histórico: não permite apagar máquina referenciada por O.S.,
-- execução de preventiva, preventiva cadastrada ou registro legado sem ID.
create or replace function public.erimax_bloquear_exclusao_maquina_vinculada()
returns trigger
language plpgsql
set search_path=''
as $$
begin
  if exists(select 1 from public.os o where o.maquina_id=old.id)
     or exists(select 1 from public.preventivas p where old.id=any(coalesce(p.maquinas_ids,'{}'::bigint[])))
     or exists (
       select 1 from public.os o
       where o.maquina_id is null
         and lower(btrim(o.setor))=lower(btrim(old.setor))
         and lower(btrim(o.maquina))=lower(btrim(old.nome))
     )
     or exists (
       select 1 from public.preventivas p
       where cardinality(coalesce(p.maquinas_ids,'{}'::bigint[]))=0
         and lower(btrim(p.setor))=lower(btrim(old.setor))
         and (
           exists (
             select 1 from jsonb_array_elements_text(coalesce(p.maquinas,'[]'::jsonb)) as n(nome)
             where lower(btrim(n.nome))=lower(btrim(old.nome))
           )
           or (
             jsonb_array_length(coalesce(p.maquinas,'[]'::jsonb))=0
             and lower(btrim(p.maquina))=lower(btrim(old.nome))
           )
         )
     )
     or exists (
       select 1
       from public.os o
       cross join lateral jsonb_array_elements(coalesce(o.maquinas_execucao,'[]'::jsonb)) as item(value)
       where lower(btrim(o.setor))=lower(btrim(old.setor))
         and (
           (item.value ? 'maquina_id'
             and (item.value->>'maquina_id') ~ '^[0-9]+$'
             and (item.value->>'maquina_id')::bigint=old.id)
           or (
             nullif(item.value->>'maquina_id','') is null
             and lower(btrim(coalesce(item.value->>'nome','')))=lower(btrim(old.nome))
           )
         )
     ) then
    raise exception 'Máquina vinculada a O.S. ou preventiva. Preserve o cadastro para manter o histórico.';
  end if;

  return old;
end;
$$;

drop trigger if exists trg_erimax_bloquear_exclusao_maquina_vinculada on public.maquinas;
create trigger trg_erimax_bloquear_exclusao_maquina_vinculada
before delete on public.maquinas
for each row execute function public.erimax_bloquear_exclusao_maquina_vinculada();

-- Mantém a validação original de gestor, justificativa, cronologia e materiais;
-- exige também o identificador correto da máquina ao editar uma O.S.
create or replace function public.erimax_editar_os_completa(p_os_id bigint,p_dados jsonb,p_motivo text)
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
  v_maquina_id bigint;
begin
  if (select auth.uid()) is null then raise exception 'Sessão não autenticada.'; end if;
  select p.perfil,p.nome into v_perfil,v_nome
  from public.perfis p where p.id=(select auth.uid());
  if v_perfil is distinct from 'gestor' then raise exception 'Somente o gestor pode editar todos os dados da O.S.'; end if;
  if length(trim(coalesce(p_motivo,'')))<8 then raise exception 'Informe uma justificativa com pelo menos 8 caracteres.'; end if;
  if jsonb_typeof(p_dados) is distinct from 'object' then raise exception 'Dados da O.S. inválidos.'; end if;

  select to_jsonb(o) into v_antigo
  from public.os o where o.id=p_os_id for update;
  if v_antigo is null then raise exception 'O.S. não encontrada.'; end if;

  if coalesce(p_dados->>'maquina','')='' or coalesce(p_dados->>'setor','')='' or coalesce(p_dados->>'turno','')='' then
    raise exception 'Máquina, setor e turno são obrigatórios.';
  end if;

  v_maquina_id:=nullif(p_dados->>'maquina_id','')::bigint;
  if v_maquina_id is null then
    -- Compatibilidade com versões antigas do app: resolve somente se nome + setor forem únicos.
    select count(*),min(m.id)
      into v_quantidade,v_maquina_id
    from public.maquinas m
    where lower(btrim(m.nome))=lower(btrim(p_dados->>'maquina'))
      and lower(btrim(m.setor))=lower(btrim(p_dados->>'setor'));
    if v_quantidade<>1 then
      raise exception 'Não foi possível identificar uma única máquina. Atualize o aplicativo e selecione pelo código.';
    end if;
  elsif not exists (
    select 1 from public.maquinas m
    where m.id=v_maquina_id
      and lower(btrim(m.nome))=lower(btrim(p_dados->>'maquina'))
      and lower(btrim(m.setor))=lower(btrim(p_dados->>'setor'))
  ) then
    raise exception 'O ID da máquina não corresponde ao nome e setor selecionados.';
  end if;

  if coalesce(p_dados->>'situacao_equipamento','') not in ('Rodando','Parado') then
    raise exception 'Selecione se a máquina estava Rodando ou Parada.';
  end if;
  if coalesce(p_dados->>'prioridade','') not in ('Baixa','Média','Alta','Urgente','Crítica','Critica') then
    raise exception 'Prioridade inválida.';
  end if;
  if coalesce(p_dados->>'tipo','')='' or coalesce(p_dados->>'descricao','')='' then
    raise exception 'Tipo e descrição são obrigatórios.';
  end if;
  if nullif(p_dados->>'created_at','') is null then
    raise exception 'Informe a data de abertura.';
  end if;
  if nullif(p_dados->>'data_atendimento','') is not null
     and (p_dados->>'data_atendimento')::timestamptz < (p_dados->>'created_at')::timestamptz then
    raise exception 'Atendimento não pode ser anterior à abertura.';
  end if;
  if nullif(p_dados->>'data_conclusao','') is not null and (p_dados->>'data_atendimento') is null then
    raise exception 'Informe o início do atendimento antes da conclusão.';
  end if;
  if nullif(p_dados->>'data_conclusao','') is not null
     and (p_dados->>'data_conclusao')::timestamptz < (p_dados->>'data_atendimento')::timestamptz then
    raise exception 'Conclusão não pode ser anterior ao atendimento.';
  end if;

  if p_dados ? 'materiais_utilizados' then
    v_materiais:=coalesce(p_dados->'materiais_utilizados','[]'::jsonb);
    if jsonb_typeof(v_materiais) is distinct from 'array' then
      raise exception 'Lista de materiais inválida.';
    end if;
    v_peca:=nullif(trim(coalesce(v_materiais->0->>'nome','')),'');
    v_qtd:=coalesce(nullif(v_materiais->0->>'quantidade','')::numeric,1);
  else
    v_materiais:=coalesce(v_antigo->'materiais_utilizados','[]'::jsonb);
    v_peca:=nullif(p_dados->>'peca','');
    v_qtd:=coalesce(nullif(p_dados->>'peca_quantidade','')::numeric,(v_antigo->>'peca_quantidade')::numeric,1);
  end if;

  update public.os set
    maquina=p_dados->>'maquina',
    maquina_id=v_maquina_id,
    setor=p_dados->>'setor',
    turno=p_dados->>'turno',
    tipo=p_dados->>'tipo',
    prioridade=p_dados->>'prioridade',
    descricao=p_dados->>'descricao',
    tecnico=nullif(p_dados->>'tecnico',''),
    situacao_equipamento=p_dados->>'situacao_equipamento',
    causa=nullif(p_dados->>'causa',''),
    peca=v_peca,
    peca_quantidade=v_qtd,
    materiais_utilizados=v_materiais,
    servico_executado=nullif(p_dados->>'servico_executado',''),
    created_at=(p_dados->>'created_at')::timestamptz,
    data_atendimento=nullif(p_dados->>'data_atendimento','')::timestamptz,
    data_conclusao=nullif(p_dados->>'data_conclusao','')::timestamptz,
    rodando_em=nullif(p_dados->>'rodando_em','')::timestamptz,
    observacao_rodando=nullif(p_dados->>'observacao_rodando',''),
    ajustado_por=v_nome,
    ajustado_em=now(),
    ajuste_obs=trim(p_motivo)
  where id=p_os_id;
end
$function$;
