-- Permite transferência para técnico em expediente com status ONLINE ou EM SERVIÇO.
CREATE OR REPLACE FUNCTION public.erimax_solicitar_transferencia_os(p_os_id bigint, p_tecnico_destino text, p_motivo text)
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
    AND (p.perfil = 'tecnico' OR p.id = 'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid)
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
$function$
;
REVOKE ALL ON FUNCTION public.erimax_solicitar_transferencia_os(bigint,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.erimax_solicitar_transferencia_os(bigint,text,text) FROM anon;
GRANT EXECUTE ON FUNCTION public.erimax_solicitar_transferencia_os(bigint,text,text) TO authenticated;
