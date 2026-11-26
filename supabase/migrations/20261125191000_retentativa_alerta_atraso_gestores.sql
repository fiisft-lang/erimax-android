-- Controle individual de entrega do alerta de atraso aos gestores.
-- Migration exclusiva da branch de testes até aprovação explícita.

alter table public.preventiva_execucoes
  add column if not exists atraso_destinatarios jsonb not null default '[]'::jsonb,
  add column if not exists atraso_processando_em timestamptz;

alter table public.preventiva_execucoes
  drop constraint if exists preventiva_execucoes_atraso_destinatarios_array_check;

alter table public.preventiva_execucoes
  add constraint preventiva_execucoes_atraso_destinatarios_array_check
  check (jsonb_typeof(atraso_destinatarios) = 'array');
