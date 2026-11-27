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
revoke all on public.almox_retiradas_avulsas from anon;
revoke insert, update, delete on public.almox_retiradas_avulsas from authenticated;
grant select on public.almox_retiradas_avulsas to authenticated;
drop policy if exists almox_retiradas_avulsas_select on public.almox_retiradas_avulsas;
create policy almox_retiradas_avulsas_select on public.almox_retiradas_avulsas for select to authenticated using (auth.uid() is not null and (criado_por = auth.uid() or public.meu_perfil() = 'gestor'));
revoke insert, update, delete on public.almox_retiradas_avulsas from anon, authenticated;

create or replace function public.almox_aplicar_movimentacao()
returns trigger language plpgsql security definer set search_path to 'public','pg_temp' as $function$
declare
  v_saldo numeric(14,3);
  v_novo numeric(14,3);
  v_auto_os boolean := coalesce(current_setting('erimax.almox_auto_os', true), '') = 'on' and new.os_id is not null and (new.chave_idempotencia like 'os:%:consumo:%' or new.chave_idempotencia like 'os:%:estorno:%');
  v_auto_avulsa boolean := coalesce(current_setting('erimax.almox_auto_avulsa', true), '') = 'on' and new.os_id is null and new.chave_idempotencia like 'retirada-avulsa:%';
begin
  if auth.uid() is null or (coalesce(public.meu_perfil(),'') <> 'gestor' and not v_auto_os and not v_auto_avulsa) then raise exception 'Somente o Gestor pode movimentar o estoque manualmente.'; end if;
  select quantidade_atual into v_saldo from public.almox_materiais where id=new.material_id and ativo=true for update;
  if not found then raise exception 'Material não encontrado ou inativo.'; end if;
  if new.tipo='entrada' then v_novo:=v_saldo+new.quantidade; elsif new.tipo='saida' then if v_saldo<new.quantidade then raise exception 'Estoque insuficiente. Disponível: %',v_saldo; end if; v_novo:=v_saldo-new.quantidade; else v_novo:=new.quantidade; end if;
  new.saldo_anterior:=v_saldo; new.saldo_posterior:=v_novo;
  update public.almox_materiais set quantidade_atual=v_novo,atualizado_em=now() where id=new.material_id;
  return new;
end; $function$;

create or replace function public.almox_registrar_retirada_avulsa(p_itens jsonb,p_destino text,p_motivo text)
returns uuid language plpgsql security definer set search_path = '' as $function$
declare v_uid uuid:=auth.uid(); v_item jsonb; v_material public.almox_materiais%rowtype; v_qtd numeric(14,3); v_itens jsonb:='[]'::jsonb; v_id uuid; v_idx integer:=0; v_mov uuid;
begin
  if v_uid is null then raise exception 'Sessão não autenticada.'; end if;
  if coalesce(public.meu_perfil(),'') not in ('gestor','tecnico','operador') then raise exception 'Seu perfil não pode registrar retiradas.'; end if;
  if jsonb_typeof(coalesce(p_itens,'null'::jsonb))<>'array' then raise exception 'A lista de materiais é inválida.'; end if;
  if jsonb_array_length(p_itens)<1 or jsonb_array_length(p_itens)>30 then raise exception 'Adicione de 1 a 30 materiais.'; end if;
  if length(trim(coalesce(p_destino,''))) not between 2 and 120 then raise exception 'Informe o destino da retirada.'; end if;
  if length(trim(coalesce(p_motivo,''))) not between 3 and 240 then raise exception 'Informe o motivo da retirada.'; end if;
  for v_item in select value from jsonb_array_elements(p_itens) loop
    if coalesce(v_item->>'material_id','') !~* '^[0-9a-f-]{36}$' then raise exception 'Material inválido na retirada.'; end if;
    if coalesce(v_item->>'quantidade','') !~ '^[0-9]+([.][0-9]+)?$' then raise exception 'Quantidade inválida.'; end if;
    v_qtd:=(v_item->>'quantidade')::numeric(14,3); if v_qtd<=0 then raise exception 'A quantidade precisa ser maior que zero.'; end if;
    select * into v_material from public.almox_materiais where id=(v_item->>'material_id')::uuid and ativo=true for update;
    if not found then raise exception 'Um dos materiais não está cadastrado ou está inativo.'; end if;
    v_itens:=v_itens||jsonb_build_array(jsonb_build_object('material_id',v_material.id,'nome',v_material.nome,'unidade',v_material.unidade,'quantidade',v_qtd));
  end loop;
  insert into public.almox_retiradas_avulsas(itens,destino,motivo,status,criado_por,analisado_por,analisado_em) values(v_itens,trim(p_destino),trim(p_motivo),'aprovada',v_uid,v_uid,now()) returning id into v_id;
  perform set_config('erimax.almox_auto_avulsa','on',true);
  for v_item in select value from jsonb_array_elements(v_itens) loop v_idx:=v_idx+1;
    insert into public.almox_movimentacoes(material_id,tipo,quantidade,motivo,os_id,solicitacao_id,chave_idempotencia,criado_por)
    values((v_item->>'material_id')::uuid,'saida',(v_item->>'quantidade')::numeric,left('Retirada avulsa — '||trim(p_destino)||' — '||trim(p_motivo),240),null,null,'retirada-avulsa:'||v_id::text||':'||v_idx::text,v_uid) returning id into v_mov;
  end loop;
  perform set_config('erimax.almox_auto_avulsa','off',true); return v_id;
end; $function$;
revoke all on function public.almox_registrar_retirada_avulsa(jsonb,text,text) from public,anon,authenticated;
grant execute on function public.almox_registrar_retirada_avulsa(jsonb,text,text) to authenticated;
revoke all on function public.almox_solicitar_retirada_avulsa(jsonb,text,text) from public,anon,authenticated;
revoke all on function public.almox_aprovar_retirada_avulsa(uuid) from public,anon,authenticated;
revoke all on function public.almox_recusar_retirada_avulsa(uuid,text) from public,anon,authenticated;