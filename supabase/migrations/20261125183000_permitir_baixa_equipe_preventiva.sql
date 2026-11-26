-- Permite que integrantes cadastrados na equipe de uma O.S. preventiva salvem
-- somente o progresso individual das máquinas, sem ampliar a policy geral de O.S.

create or replace function public.erimax_salvar_progresso_preventiva(
  p_os_id bigint,
  p_maquinas_execucao jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid;
  v_nome text;
  v_perfil text;
  v_os public.os%rowtype;
  v_item jsonb;
  v_original jsonb;
  v_ordem bigint;
begin
  v_uid := (select auth.uid());
  if v_uid is null then
    raise exception 'Sessão não autenticada.';
  end if;

  select p.nome, p.perfil
    into v_nome, v_perfil
  from public.perfis p
  where p.id = v_uid;

  if v_perfil is distinct from 'tecnico'
     and v_uid not in (
       'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid,
       'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c'::uuid
     ) then
    raise exception 'Somente integrantes técnicos da equipe podem salvar o andamento.';
  end if;

  select o.*
    into v_os
  from public.os o
  where o.id = p_os_id
  for update;

  if not found then
    raise exception 'O.S. não encontrada.';
  end if;

  if v_os.tipo is distinct from 'Preventiva'
     or v_os.status not in ('Em Atendimento', 'Pausada') then
    raise exception 'Esta O.S. não aceita atualização de progresso preventivo.';
  end if;

  if v_os.tecnico is distinct from v_nome
     and not coalesce(v_os.tecnicos_participantes, '[]'::jsonb) @> jsonb_build_array(v_nome) then
    raise exception 'Você não faz parte da equipe desta preventiva.';
  end if;

  if jsonb_typeof(p_maquinas_execucao) is distinct from 'array' then
    raise exception 'Lista de máquinas inválida.';
  end if;

  if jsonb_array_length(p_maquinas_execucao) <>
     jsonb_array_length(coalesce(v_os.maquinas_execucao, '[]'::jsonb)) then
    raise exception 'A lista de máquinas não corresponde à O.S. original.';
  end if;

  for v_item, v_ordem in
    select e.value, e.ordinality
    from jsonb_array_elements(p_maquinas_execucao) with ordinality as e(value, ordinality)
  loop
    v_original := coalesce(v_os.maquinas_execucao, '[]'::jsonb) -> (v_ordem - 1);

    if (v_item - 'concluida' - 'concluida_em') is distinct from
       (v_original - 'concluida' - 'concluida_em') then
      raise exception 'Não é permitido alterar a identidade ou a ordem das máquinas.';
    end if;

    if jsonb_typeof(v_item -> 'concluida') is distinct from 'boolean' then
      raise exception 'Informe o estado de conclusão de cada máquina.';
    end if;

    if (v_item ->> 'concluida')::boolean
       and nullif(v_item ->> 'concluida_em', '') is null then
      raise exception 'Informe a data da baixa da máquina concluída.';
    end if;

    if not (v_item ->> 'concluida')::boolean
       and nullif(v_item ->> 'concluida_em', '') is not null then
      raise exception 'Máquina pendente não pode manter data de conclusão.';
    end if;
  end loop;

  update public.os
     set maquinas_execucao = p_maquinas_execucao
   where id = p_os_id;
end;
$$;

revoke all on function public.erimax_salvar_progresso_preventiva(bigint, jsonb) from public;
revoke all on function public.erimax_salvar_progresso_preventiva(bigint, jsonb) from anon;
grant execute on function public.erimax_salvar_progresso_preventiva(bigint, jsonb) to authenticated;
