-- Preventivas com várias máquinas e acompanhamento individual na mesma O.S.
ALTER TABLE public.preventivas
  ADD COLUMN IF NOT EXISTS maquinas jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS tecnicos_participantes jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.os
  ADD COLUMN IF NOT EXISTS maquinas_execucao jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS tecnicos_participantes jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE public.preventivas
  ADD CONSTRAINT preventivas_maquinas_array_check
  CHECK (jsonb_typeof(maquinas) = 'array');

ALTER TABLE public.os
  ADD CONSTRAINT os_maquinas_execucao_array_check
  CHECK (jsonb_typeof(maquinas_execucao) = 'array');

ALTER TABLE public.preventivas
  ADD CONSTRAINT preventivas_tecnicos_participantes_array_check
  CHECK (jsonb_typeof(tecnicos_participantes) = 'array');

ALTER TABLE public.os
  ADD CONSTRAINT os_tecnicos_participantes_array_check
  CHECK (jsonb_typeof(tecnicos_participantes) = 'array');
