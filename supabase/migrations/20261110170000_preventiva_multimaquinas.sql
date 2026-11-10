-- Preventivas com várias máquinas e equipe de manutentores na mesma O.S.
ALTER TABLE public.preventivas
  ADD COLUMN IF NOT EXISTS maquinas jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS tecnicos_participantes jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.os
  ADD COLUMN IF NOT EXISTS maquinas_execucao jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS tecnicos_participantes jsonb NOT NULL DEFAULT '[]'::jsonb;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'preventivas_maquinas_array_check' AND conrelid = 'public.preventivas'::regclass) THEN
    ALTER TABLE public.preventivas ADD CONSTRAINT preventivas_maquinas_array_check CHECK (jsonb_typeof(maquinas) = 'array');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'os_maquinas_execucao_array_check' AND conrelid = 'public.os'::regclass) THEN
    ALTER TABLE public.os ADD CONSTRAINT os_maquinas_execucao_array_check CHECK (jsonb_typeof(maquinas_execucao) = 'array');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'preventivas_tecnicos_participantes_array_check' AND conrelid = 'public.preventivas'::regclass) THEN
    ALTER TABLE public.preventivas ADD CONSTRAINT preventivas_tecnicos_participantes_array_check CHECK (jsonb_typeof(tecnicos_participantes) = 'array');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'os_tecnicos_participantes_array_check' AND conrelid = 'public.os'::regclass) THEN
    ALTER TABLE public.os ADD CONSTRAINT os_tecnicos_participantes_array_check CHECK (jsonb_typeof(tecnicos_participantes) = 'array');
  END IF;
END $$;
