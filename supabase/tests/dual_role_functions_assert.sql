-- Testes funcionais da migration de dupla função.
INSERT INTO public.perfis (id, nome, perfil) VALUES
  ('e978d5b1-9382-41de-be43-549a4e1e081e', 'Fii', 'gestor'),
  ('c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', 'Guilherme', 'gestor'),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'Outro Gestor', 'gestor'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'Técnico Base', 'tecnico');

INSERT INTO public.status_tecnicos (user_id, status, turno_ativo) VALUES
  ('e978d5b1-9382-41de-be43-549a4e1e081e', 'ONLINE', true),
  ('c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', 'ONLINE', true),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'ONLINE', true);

INSERT INTO public.os (id, status, tecnico) VALUES
  (1, 'Em Atendimento', 'Técnico Base'),
  (2, 'Em Atendimento', 'Técnico Base'),
  (3, 'Em Atendimento', 'Técnico Base'),
  (4, 'Em Atendimento', 'Técnico Base');

-- Fii solicita transferência para Guilherme; Guilherme aceita.
SELECT set_config('request.jwt.claim.sub', 'e978d5b1-9382-41de-be43-549a4e1e081e', false);
SELECT public.erimax_solicitar_transferencia_os(1, 'Guilherme', 'Teste de transferência');
SELECT set_config('request.jwt.claim.sub', 'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', false);
SELECT public.erimax_aceitar_transferencia_os(1);

DO $assert_guilherme_aceitou$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.os
    WHERE id = 1 AND tecnico = 'Guilherme' AND transferencia_para IS NULL
  ) THEN
    RAISE EXCEPTION 'Guilherme não conseguiu aceitar a transferência.';
  END IF;
END;
$assert_guilherme_aceitou$;

-- Guilherme solicita transferência para Fii; Fii aceita.
SELECT set_config('request.jwt.claim.sub', 'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', false);
SELECT public.erimax_solicitar_transferencia_os(2, 'Fii', 'Teste de transferência');
SELECT set_config('request.jwt.claim.sub', 'e978d5b1-9382-41de-be43-549a4e1e081e', false);
SELECT public.erimax_aceitar_transferencia_os(2);

DO $assert_fii_aceitou$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.os
    WHERE id = 2 AND tecnico = 'Fii' AND transferencia_para IS NULL
  ) THEN
    RAISE EXCEPTION 'Fii não conseguiu aceitar a transferência.';
  END IF;
END;
$assert_fii_aceitou$;

-- Os dois também conseguem recusar transferências destinadas a eles.
SELECT set_config('request.jwt.claim.sub', 'e978d5b1-9382-41de-be43-549a4e1e081e', false);
SELECT public.erimax_solicitar_transferencia_os(3, 'Guilherme', 'Teste de recusa');
SELECT set_config('request.jwt.claim.sub', 'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', false);
SELECT public.erimax_recusar_transferencia_os(3);

SELECT set_config('request.jwt.claim.sub', 'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', false);
SELECT public.erimax_solicitar_transferencia_os(4, 'Fii', 'Teste de recusa');
SELECT set_config('request.jwt.claim.sub', 'e978d5b1-9382-41de-be43-549a4e1e081e', false);
SELECT public.erimax_recusar_transferencia_os(4);

DO $assert_recusas$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.os
    WHERE id IN (3,4) AND transferencia_para IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A recusa não limpou a transferência pendente.';
  END IF;
END;
$assert_recusas$;

-- Fii e Guilherme podem salvar progresso preventivo quando fazem parte da equipe.
INSERT INTO public.os (id, status, tecnico, tipo, tecnicos_participantes, maquinas_execucao)
VALUES
  (5, 'Em Atendimento', 'Guilherme', 'Preventiva', '[]'::jsonb,
   '[{"codigo":"M-01","concluida":false,"concluida_em":null}]'::jsonb),
  (6, 'Em Atendimento', 'Técnico Base', 'Preventiva', '["Fii"]'::jsonb,
   '[{"codigo":"M-02","concluida":false,"concluida_em":null}]'::jsonb);

SELECT set_config('request.jwt.claim.sub', 'c1b96ae1-aa45-4563-83f6-a9cb33aa0a1c', false);
SELECT public.erimax_salvar_progresso_preventiva(
  5, '[{"codigo":"M-01","concluida":true,"concluida_em":"2026-11-26T12:00:00Z"}]'::jsonb
);
SELECT set_config('request.jwt.claim.sub', 'e978d5b1-9382-41de-be43-549a4e1e081e', false);
SELECT public.erimax_salvar_progresso_preventiva(
  6, '[{"codigo":"M-02","concluida":true,"concluida_em":"2026-11-26T12:00:00Z"}]'::jsonb
);

DO $assert_preventiva$
BEGIN
  IF jsonb_array_length((SELECT maquinas_execucao FROM public.os WHERE id = 5)) <> 1
     OR (SELECT maquinas_execucao -> 0 ->> 'concluida' FROM public.os WHERE id = 5) <> 'true'
     OR (SELECT maquinas_execucao -> 0 ->> 'concluida' FROM public.os WHERE id = 6) <> 'true' THEN
    RAISE EXCEPTION 'Fii ou Guilherme não conseguiu salvar o progresso preventivo.';
  END IF;
END;
$assert_preventiva$;

-- Outro gestor não recebe acesso técnico automaticamente.
SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', false);
DO $assert_outro_gestor_bloqueado$
BEGIN
  BEGIN
    PERFORM public.erimax_salvar_progresso_preventiva(
      5, '[{"codigo":"M-01","concluida":false,"concluida_em":null}]'::jsonb
    );
    RAISE EXCEPTION 'Outro gestor recebeu acesso técnico indevido.';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'Outro gestor recebeu acesso técnico indevido.' THEN
        RAISE;
      END IF;
      IF SQLERRM NOT LIKE 'Somente integrantes técnicos%' THEN
        RAISE;
      END IF;
  END;
END;
$assert_outro_gestor_bloqueado$;

DO $assert_grants$
BEGIN
  IF NOT has_function_privilege('authenticated', 'public.erimax_aceitar_transferencia_os(bigint)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.erimax_aceitar_transferencia_os(bigint)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.erimax_salvar_progresso_preventiva(bigint,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.erimax_salvar_progresso_preventiva(bigint,jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'Permissões EXECUTE não correspondem ao esperado.';
  END IF;
END;
$assert_grants$;
