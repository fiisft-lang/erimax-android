-- Registra quem abriu a O.S. e a situação inicial do equipamento.
-- Também garante que o início do atendimento nunca seja anterior à abertura.

ALTER TABLE public.os
  ADD COLUMN IF NOT EXISTS aberto_por text,
  ADD COLUMN IF NOT EXISTS situacao_equipamento text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.os'::regclass
      AND conname = 'os_situacao_equipamento_check'
  ) THEN
    ALTER TABLE public.os
      ADD CONSTRAINT os_situacao_equipamento_check
      CHECK (situacao_equipamento IS NULL OR situacao_equipamento IN ('Parado', 'Rodando'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.os'::regclass
      AND conname = 'os_aberto_por_nao_vazio_check'
  ) THEN
    ALTER TABLE public.os
      ADD CONSTRAINT os_aberto_por_nao_vazio_check
      CHECK (aberto_por IS NULL OR length(btrim(aberto_por)) > 0);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.erimax_corrigir_inicio_os()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.status = 'Em Atendimento'
     AND OLD.status IS DISTINCT FROM 'Em Atendimento' THEN
    NEW.data_atendimento := GREATEST(
      COALESCE(NEW.created_at, clock_timestamp()),
      clock_timestamp()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_erimax_corrigir_inicio_os ON public.os;
CREATE TRIGGER trg_erimax_corrigir_inicio_os
BEFORE UPDATE OF status ON public.os
FOR EACH ROW
EXECUTE FUNCTION public.erimax_corrigir_inicio_os();
