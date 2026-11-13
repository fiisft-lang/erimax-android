create table if not exists public.os_historico_equipamento (
  id bigint generated always as identity primary key,
  os_id bigint not null references public.os(id) on delete cascade,
  equipamento_anterior text not null,
  equipamento_novo text not null,
  usuario_id uuid not null references auth.users(id),
  usuario_nome text not null,
  alterado_em timestamptz not null default now()
);

alter table public.os_historico_equipamento enable row level security;
revoke all on table public.os_historico_equipamento from anon, authenticated;

create or replace function public.corrigir_equipamento_os(p_os_id bigint, p_nova_maquina text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_perfil text;
  v_nome text;
  v_setor text;
  v_maquina_anterior text;
  v_nova_maquina text := btrim(coalesce(p_nova_maquina, ''));
begin
  if auth.uid() is null then
    raise exception 'É necessário estar autenticado para corrigir o equipamento.' using errcode = '42501';
  end if;

  v_perfil := public.meu_perfil();
  if v_perfil not in ('operador', 'gestor') then
    raise exception 'Somente operadoras e gestores podem corrigir o equipamento.' using errcode = '42501';
  end if;

  if length(v_nova_maquina) < 2 or length(v_nova_maquina) > 150 then
    raise exception 'Selecione um equipamento válido.' using errcode = '22023';
  end if;

  select o.maquina, o.setor
    into v_maquina_anterior, v_setor
  from public.os o
  where o.id = p_os_id
    and o.status in ('Aberta', 'Em Atendimento', 'Pausada', 'Concluída')
  for update;

  if not found then
    raise exception 'O.S. não encontrada ou não disponível para correção.' using errcode = 'P0002';
  end if;

  if v_maquina_anterior = v_nova_maquina then
    return;
  end if;

  if not exists (
    select 1
    from public.maquinas m
    where lower(btrim(m.nome)) = lower(v_nova_maquina)
      and lower(btrim(m.setor)) = lower(btrim(v_setor))
  ) then
    raise exception 'O equipamento escolhido não está cadastrado neste setor.' using errcode = '22023';
  end if;

  select p.nome into v_nome
  from public.perfis p
  where p.id = auth.uid();

  update public.os
  set maquina = v_nova_maquina
  where id = p_os_id;

  insert into public.os_historico_equipamento
    (os_id, equipamento_anterior, equipamento_novo, usuario_id, usuario_nome)
  values
    (p_os_id, coalesce(v_maquina_anterior, ''), v_nova_maquina, auth.uid(), coalesce(v_nome, 'Usuário'));
end;
$function$;

revoke all on function public.corrigir_equipamento_os(bigint, text) from public, anon;
grant execute on function public.corrigir_equipamento_os(bigint, text) to authenticated;