-- Aceitar transferência valida o turno ativo, não o rótulo derivado do status.
-- O status EM SERVIÇO é atribuído quando o técnico já possui uma O.S. ativa;
-- turno_ativo continua indicando se ele está dentro do expediente.
-- A checagem seguinte impede aceitar se houver outra O.S. em atendimento.
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
    AND (p.perfil = 'tecnico' OR p.id = 'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid);

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

REVOKE ALL ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) FROM anon;
GRANT EXECUTE ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) TO authenticated;
