-- Corrige registros antigos com horário de início anterior à abertura.
-- A proteção de edição manual fica suspensa apenas durante esta migração administrativa.
ALTER TABLE public.os DISABLE TRIGGER trg_erimax_protege_horarios_os;

UPDATE public.os
SET data_atendimento = created_at
WHERE data_atendimento IS NOT NULL
  AND data_atendimento < created_at;

ALTER TABLE public.os ENABLE TRIGGER trg_erimax_protege_horarios_os;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.os'::regclass
      AND conname = 'os_atendimento_nao_antes_da_abertura_check'
  ) THEN
    ALTER TABLE public.os
      ADD CONSTRAINT os_atendimento_nao_antes_da_abertura_check
      CHECK (data_atendimento IS NULL OR data_atendimento >= created_at);
  END IF;
END $$;
