create or replace function public.reabrir_os_concluida(p_os_id bigint, p_motivo text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_os public.os%rowtype;
  v_nome_gestor text;
  v_tecnico_id uuid;
  v_outra_ativa boolean;
  v_maquinas jsonb;
begin
  if auth.uid() is null then
    raise exception 'É necessário entrar no sistema para reabrir a O.S.';
  end if;

  if public.meu_perfil() <> 'gestor' then
    raise exception 'Somente o gestor pode reabrir uma O.S.';
  end if;

  select p.nome into v_nome_gestor
  from public.perfis p
  where p.id = auth.uid();

  if v_nome_gestor is null then
    raise exception 'Perfil do gestor não encontrado.';
  end if;

  if p_motivo is null or length(btrim(p_motivo)) < 8 then
    raise exception 'Informe um motivo com pelo menos 8 caracteres.';
  end if;

  select * into v_os
  from public.os
  where id = p_os_id
  for update;

  if not found then
    raise exception 'O.S. não encontrada.';
  end if;

  if v_os.status <> 'Concluída' then
    raise exception 'Somente uma O.S. concluída pode ser reaberta.';
  end if;

  select p.id into v_tecnico_id
  from public.perfis p
  where p.nome = v_os.tecnico
    and p.perfil = 'tecnico'
  order by p.id
  limit 1;

  if v_tecnico_id is null then
    raise exception 'O técnico responsável por esta O.S. não foi encontrado no cadastro.';
  end if;

  select exists (
    select 1 from public.os o
    where o.tecnico = v_os.tecnico
      and o.status = 'Em Atendimento'
      and o.id <> p_os_id
  ) into v_outra_ativa;

  if v_outra_ativa then
    raise exception 'O técnico responsável já possui outra O.S. em atendimento. Finalize ou transfira essa ordem antes de reabrir.';
  end if;

  insert into public.historico_reaberturas_os
    (os_id, reaberta_por, tecnico_nome, motivo, dados_conclusao)
  values
    (v_os.id, auth.uid(), v_os.tecnico, btrim(p_motivo),
      jsonb_build_object(
        'status', v_os.status,
        'data_conclusao', v_os.data_conclusao,
        'causa', v_os.causa,
        'peca', v_os.peca,
        'servico_executado', v_os.servico_executado,
        'maquinas_execucao', v_os.maquinas_execucao,
        'ajustado_por', v_os.ajustado_por,
        'ajustado_em', v_os.ajustado_em,
        'ajuste_obs', v_os.ajuste_obs
      ));

  select coalesce(
    jsonb_agg(
      (m - 'concluida' - 'concluida_em')
      || jsonb_build_object('concluida', false, 'concluida_em', null)
    ),
    '[]'::jsonb
  ) into v_maquinas
  from jsonb_array_elements(coalesce(v_os.maquinas_execucao, '[]'::jsonb)) as itens(m);

  update public.os
  set status = 'Em Atendimento',
      data_conclusao = null,
      causa = null,
      peca = null,
      servico_executado = null,
      maquinas_execucao = v_maquinas,
      ajustado_por = null,
      ajustado_em = null,
      ajuste_obs = null
  where id = p_os_id;

  update public.status_tecnicos
  set status = 'EM SERVIÇO',
      os_atual_id = p_os_id,
      atualizado_em = now()
  where user_id = v_tecnico_id;
end;
$function$;

revoke all on function public.reabrir_os_concluida(bigint, text) from public, anon;
grant execute on function public.reabrir_os_concluida(bigint, text) to authenticated;
