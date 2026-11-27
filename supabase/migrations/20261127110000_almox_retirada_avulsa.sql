create table if not exists public.almox_retiradas_avulsas (
  id uuid primary key default gen_random_uuid(),
  itens jsonb not null,
  destino text not null,
  motivo text not null,
  status text not null default 'pendente',
  criado_por uuid not null references auth.users(id),
  criado_em timestamptz not null default now(),
  analisado_por uuid references auth.users(id),
  analisado_em timestamptz,
  justificativa_analise text,
  constraint almox_retiradas_avulsas_itens_array check (jsonb_typeof(itens) = 'array' and jsonb_array_length(itens) between 1 and 30),
  constraint almox_retiradas_avulsas_destino_check check (length(trim(destino)) between 2 and 120),
  constraint almox_retiradas_avulsas_motivo_check check (length(trim(motivo)) between 3 and 240),
  constraint almox_retiradas_avulsas_status_check check (status in ('pendente','aprovada','recusada'))
);
alter table public.almox_retiradas_avulsas enable row level security;
grant select on public.almox_retiradas_avulsas to authenticated;
drop policy if exists almox_retiradas_avulsas_select on public.almox_retiradas_avulsas;
create policy almox_retiradas_avulsas_select on public.almox_retiradas_avulsas for select to authenticated using (auth.uid() is not null and (criado_por = auth.uid() or public.meu_perfil() = 'gestor'));
revoke insert, update, delete on public.almox_retiradas_avulsas from anon, authenticated;

create or replace function public.almox_solicitar_retirada_avulsa(p_itens jsonb, p_destino text, p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_item jsonb;
  v_material public.almox_materiais%rowtype;
  v_qtd numeric(14,3);
  v_itens jsonb := '[]'::jsonb;
  v_id uuid;
begin
  if v_uid is null then raise exception 'Sessão não autenticada.'; end if;
  if coalesce(public.meu_perfil(),'') not in ('gestor','tecnico','operador') then raise exception 'Seu perfil não pode solicitar materiais.'; end if;
  if jsonb_typeof(coalesce(p_itens,'null'::jsonb)) <> 'array' or jsonb_array_length(p_itens) < 1 or jsonb_array_length(p_itens) > 30 then raise exception 'Adicione de 1 a 30 materiais.'; end if;
  if length(trim(coalesce(p_destino,''))) not between 2 and 120 then raise exception 'Informe o destino da retirada.'; end if;
  if length(trim(coalesce(p_motivo,''))) not between 3 and 240 then raise exception 'Informe o motivo da retirada.'; end if;
  for v_item in select value from jsonb_array_elements(p_itens) loop
    if coalesce(v_item->>'material_id','') !~* '^[0-9a-f-]{36}$' then raise exception 'Material inválido na solicitação.'; end if;
    if coalesce(v_item->>'quantidade','') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Quantidade inválida.'; end if;
    v_qtd := (v_item->>'quantidade')::numeric(14,3);
    if v_qtd <= 0 then raise exception 'A quantidade precisa ser maior que zero.'; end if;
    select * into v_material from public.almox_materiais where id = (v_item->>'material_id')::uuid and ativo = true;
    if not found then raise exception 'Um dos materiais não está cadastrado ou está inativo.'; end if;
    v_itens := v_itens || jsonb_build_array(jsonb_build_object('material_id',v_material.id,'nome',v_material.nome,'unidade',v_material.unidade,'quantidade',v_qtd));
  end loop;
  insert into public.almox_retiradas_avulsas(itens,destino,motivo,criado_por) values(v_itens,trim(p_destino),trim(p_motivo),v_uid) returning id into v_id;
  return v_id;
end; $$;

create or replace function public.almox_aprovar_retirada_avulsa(p_retirada_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_r public.almox_retiradas_avulsas%rowtype;
  v_item jsonb;
  v_idx integer := 0;
  v_mov uuid;
begin
  if v_uid is null or coalesce(public.meu_perfil(),'') <> 'gestor' then raise exception 'Somente o Gestor pode autorizar retiradas avulsas.'; end if;
  select * into v_r from public.almox_retiradas_avulsas where id = p_retirada_id and status = 'pendente' for update;
  if not found then raise exception 'Solicitação não encontrada ou já analisada.'; end if;
  for v_item in select value from jsonb_array_elements(v_r.itens) loop
    v_idx := v_idx + 1;
    insert into public.almox_movimentacoes(material_id,tipo,quantidade,motivo,os_id,solicitacao_id,chave_idempotencia,criado_por)
    values((v_item->>'material_id')::uuid,'saida',(v_item->>'quantidade')::numeric,
      left('Retirada avulsa — ' || v_r.destino || ' — ' || v_r.motivo,240),
      null,null,'retirada-avulsa:' || v_r.id::text || ':' || v_idx::text,v_uid)
    returning id into v_mov;
  end loop;
  update public.almox_retiradas_avulsas set status='aprovada',analisado_por=v_uid,analisado_em=now(),justificativa_analise=null where id=v_r.id;
  return v_r.id;
end; $$;

create or replace function public.almox_recusar_retirada_avulsa(p_retirada_id uuid,p_justificativa text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid(); v_id uuid;
begin
  if v_uid is null or coalesce(public.meu_perfil(),'') <> 'gestor' then raise exception 'Somente o Gestor pode recusar retiradas avulsas.'; end if;
  if length(trim(coalesce(p_justificativa,''))) < 3 then raise exception 'Informe o motivo da recusa.'; end if;
  update public.almox_retiradas_avulsas set status='recusada',analisado_por=v_uid,analisado_em=now(),justificativa_analise=left(trim(p_justificativa),240)
  where id=p_retirada_id and status='pendente' returning id into v_id;
  if v_id is null then raise exception 'Solicitação não encontrada ou já analisada.'; end if;
  return v_id;
end; $$;

revoke all on function public.almox_solicitar_retirada_avulsa(jsonb,text,text) from public;
revoke all on function public.almox_aprovar_retirada_avulsa(uuid) from public;
revoke all on function public.almox_recusar_retirada_avulsa(uuid,text) from public;
grant execute on function public.almox_solicitar_retirada_avulsa(jsonb,text,text) to authenticated;
grant execute on function public.almox_aprovar_retirada_avulsa(uuid) to authenticated;
grant execute on function public.almox_recusar_retirada_avulsa(uuid,text) to authenticated;