-- Fii e Guilherme mantêm o perfil de gestor e também podem executar ações TEC.
-- As exceções são restritas aos UUIDs definidos; os demais gestores não recebem acesso técnico.

CREATE OR REPLACE FUNCTION public.erimax_solicitar_transferencia_os(
  p_os_id bigint,
  p_tecnico_destino text,
  p_motivo text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_nome text;
  v_perfil text;
  v_destino text;
  v_destino_id uuid;
  v_status text;
  v_tecnico_atual text;
  v_status_destino text;
  v_turno_destino boolean;
BEGIN
  IF p_motivo IS NULL OR length(btrim(p_motivo)) < 3 THEN
    RAISE EXCEPTION 'Informe o motivo da transferência (mínimo de 3 caracteres).';
  END IF;

  SELECT p.nome, p.perfil INTO v_nome, v_perfil
  FROM public.perfis p
  WHERE p.id = auth.uid()
    AND (p.perfil = 'gestor' OR p.perfil = 'tecnico');

  IF v_nome IS NULL THEN
    RAISE EXCEPTION 'Somente o técnico responsável ou o gestor pode solicitar a transferência.';
  END IF;

  SELECT o.status, o.tecnico, o.transferencia_para
    INTO v_status, v_tecnico_atual, v_destino
  FROM public.os o
  WHERE o.id = p_os_id
  FOR UPDATE;

  IF NOT FOUND OR v_status <> 'Em Atendimento' THEN
    RAISE EXCEPTION 'Esta O.S. não está em atendimento e não pode ser transferida.';
  END IF;

  IF v_destino IS NOT NULL THEN
    RAISE EXCEPTION 'Esta O.S. já tem uma transferência aguardando aceite.';
  END IF;

  IF v_perfil <> 'gestor' AND v_tecnico_atual IS DISTINCT FROM v_nome THEN
    RAISE EXCEPTION 'Somente o técnico responsável ou o gestor pode transferir esta O.S.';
  END IF;

  SELECT p.id, p.nome INTO v_destino_id, v_destino
  FROM public.perfis p
  WHERE lower(btrim(p.nome)) = lower(btrim(p_tecnico_destino))
    AND (p.perfil = 'tecnico'
      OR p.id IN (
        'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid,
        'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c'::uuid
      ))
  LIMIT 1;

  IF v_destino IS NULL THEN
    RAISE EXCEPTION 'Técnico de destino não encontrado.';
  END IF;

  IF v_destino = v_tecnico_atual THEN
    RAISE EXCEPTION 'Escolha um técnico diferente do responsável atual.';
  END IF;

  SELECT s.status, s.turno_ativo
    INTO v_status_destino, v_turno_destino
  FROM public.status_tecnicos s
  WHERE s.user_id = v_destino_id;

  IF NOT FOUND OR NOT coalesce(v_turno_destino, false) OR upper(coalesce(v_status_destino, '')) NOT IN ('ONLINE', 'EM SERVIÇO') THEN
    RAISE EXCEPTION 'O técnico de destino precisa estar ONLINE e com o turno ativo.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.os o
    WHERE o.tecnico = v_destino
      AND o.status = 'Em Atendimento'
      AND o.id <> p_os_id
  ) THEN
    RAISE EXCEPTION 'O técnico de destino já está responsável por outra O.S. em atendimento.';
  END IF;

  UPDATE public.os
  SET transferencia_para = v_destino,
      transferencia_solicitada_por = v_nome,
      transferencia_solicitada_em = now(),
      transferencia_motivo = btrim(p_motivo)
  WHERE id = p_os_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.erimax_aceitar_transferencia_os(p_os_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_nome text;
  v_anterior text;
  v_solicitante text;
  v_solicitada_em timestamptz;
  v_motivo text;
  v_status text;
  v_turno_ativo boolean;
BEGIN
  SELECT p.nome INTO v_nome
  FROM public.perfis p
  WHERE p.id = auth.uid()
    AND (p.perfil = 'tecnico' OR p.id IN (
      'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid,
      'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c'::uuid
    ));

  IF v_nome IS NULL THEN
    RAISE EXCEPTION 'Somente o técnico destinatário pode aceitar a transferência.';
  END IF;

  SELECT o.status, o.tecnico, o.transferencia_solicitada_por,
         o.transferencia_solicitada_em, o.transferencia_motivo
    INTO v_status, v_anterior, v_solicitante, v_solicitada_em, v_motivo
  FROM public.os o
  WHERE o.id = p_os_id
    AND o.transferencia_para = v_nome
  FOR UPDATE;

  IF NOT FOUND OR v_status <> 'Em Atendimento' THEN
    RAISE EXCEPTION 'Não existe uma transferência pendente para você nesta O.S.';
  END IF;

  SELECT s.turno_ativo
    INTO v_turno_ativo
  FROM public.status_tecnicos s
  WHERE s.user_id = auth.uid();

  IF NOT FOUND OR NOT coalesce(v_turno_ativo, false) THEN
    RAISE EXCEPTION 'Fique ONLINE no seu turno para aceitar a responsabilidade pela O.S.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.os o
    WHERE o.tecnico = v_nome
      AND o.status = 'Em Atendimento'
      AND o.id <> p_os_id
  ) THEN
    RAISE EXCEPTION 'Você já está responsável por outra O.S. em atendimento.';
  END IF;

  UPDATE public.os
  SET tecnico = v_nome,
      transferencia_para = NULL,
      transferencia_solicitada_por = NULL,
      transferencia_solicitada_em = NULL,
      transferencia_motivo = NULL
  WHERE id = p_os_id;

  INSERT INTO public.historico_transferencias_os
    (os_id, tecnico_anterior, tecnico_novo, solicitada_por,
     solicitada_em, aceita_por, aceita_em, motivo)
  VALUES
    (p_os_id, v_anterior, v_nome, coalesce(v_solicitante, v_anterior),
     coalesce(v_solicitada_em, now()), v_nome, now(),
     coalesce(nullif(btrim(v_motivo), ''), 'Motivo não informado (solicitação anterior)'));
END;
$function$;

CREATE OR REPLACE FUNCTION public.erimax_recusar_transferencia_os(p_os_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_nome text;
  v_status text;
BEGIN
  SELECT p.nome INTO v_nome
  FROM public.perfis p
  WHERE p.id = auth.uid()
    AND (p.perfil = 'tecnico' OR p.id IN (
      'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid,
      'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c'::uuid
    ));

  IF v_nome IS NULL THEN
    RAISE EXCEPTION 'Somente o técnico destinatário pode recusar a transferência.';
  END IF;

  SELECT o.status INTO v_status
  FROM public.os o
  WHERE o.id = p_os_id
    AND o.transferencia_para = v_nome
  FOR UPDATE;

  IF NOT FOUND OR v_status <> 'Em Atendimento' THEN
    RAISE EXCEPTION 'Não existe uma transferência pendente para você nesta O.S.';
  END IF;

  UPDATE public.os
  SET transferencia_para = NULL,
      transferencia_solicitada_por = NULL,
      transferencia_solicitada_em = NULL,
      transferencia_motivo = NULL
  WHERE id = p_os_id;
END;
$function$;

CREATE OR REPLACE FUNCTION public.erimax_salvar_progresso_preventiva(
  p_os_id bigint,
  p_maquinas_execucao jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
DECLARE
  v_uid uuid;
  v_nome text;
  v_perfil text;
  v_os public.os%rowtype;
  v_item jsonb;
  v_original jsonb;
  v_ordem bigint;
BEGIN
  v_uid := (select auth.uid());
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Sessão não autenticada.';
  END IF;

  SELECT p.nome, p.perfil
    INTO v_nome, v_perfil
  FROM public.perfis p
  WHERE p.id = v_uid;

  IF v_perfil IS DISTINCT FROM 'tecnico'
     AND v_uid NOT IN (
       'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid,
       'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c'::uuid
     ) THEN
    RAISE EXCEPTION 'Somente integrantes técnicos da equipe podem salvar o andamento.';
  END IF;

  SELECT o.*
    INTO v_os
  FROM public.os o
  WHERE o.id = p_os_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'O.S. não encontrada.';
  END IF;

  IF v_os.tipo IS DISTINCT FROM 'Preventiva'
     OR v_os.status NOT IN ('Em Atendimento', 'Pausada') THEN
    RAISE EXCEPTION 'Esta O.S. não aceita atualização de progresso preventivo.';
  END IF;

  IF v_os.tecnico IS DISTINCT FROM v_nome
     AND NOT coalesce(v_os.tecnicos_participantes, '[]'::jsonb) @> jsonb_build_array(v_nome) THEN
    RAISE EXCEPTION 'Você não faz parte da equipe desta preventiva.';
  END IF;

  IF jsonb_typeof(p_maquinas_execucao) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'Lista de máquinas inválida.';
  END IF;

  IF jsonb_array_length(p_maquinas_execucao) <>
     jsonb_array_length(coalesce(v_os.maquinas_execucao, '[]'::jsonb)) THEN
    RAISE EXCEPTION 'A lista de máquinas não corresponde à O.S. original.';
  END IF;

  FOR v_item, v_ordem IN
    SELECT e.value, e.ordinality
    FROM jsonb_array_elements(p_maquinas_execucao) WITH ORDINALITY AS e(value, ordinality)
  LOOP
    v_original := coalesce(v_os.maquinas_execucao, '[]'::jsonb) -> ((v_ordem - 1)::int);

    IF (v_item - 'concluida' - 'concluida_em') IS DISTINCT FROM
       (v_original - 'concluida' - 'concluida_em') THEN
      RAISE EXCEPTION 'Não é permitido alterar a identidade ou a ordem das máquinas.';
    END IF;

    IF jsonb_typeof(v_item -> 'concluida') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'Informe o estado de conclusão de cada máquina.';
    END IF;

    IF (v_item ->> 'concluida')::boolean
       AND nullif(v_item ->> 'concluida_em', '') IS NULL THEN
      RAISE EXCEPTION 'Informe a data da baixa da máquina concluída.';
    END IF;

    IF NOT (v_item ->> 'concluida')::boolean
       AND nullif(v_item ->> 'concluida_em', '') IS NOT NULL THEN
      RAISE EXCEPTION 'Máquina pendente não pode manter data de conclusão.';
    END IF;
  END LOOP;

  UPDATE public.os
     SET maquinas_execucao = p_maquinas_execucao
   WHERE id = p_os_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.erimax_solicitar_transferencia_os(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erimax_solicitar_transferencia_os(bigint, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.erimax_recusar_transferencia_os(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.erimax_recusar_transferencia_os(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.erimax_recusar_transferencia_os(bigint) TO authenticated;
REVOKE ALL ON FUNCTION public.erimax_salvar_progresso_preventiva(bigint, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.erimax_salvar_progresso_preventiva(bigint, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.erimax_salvar_progresso_preventiva(bigint, jsonb) TO authenticated;
