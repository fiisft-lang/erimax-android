-- Campos usados pela automação para controlar entregas parciais do alerta de atraso.
-- Esta migration permanece somente na branch de testes até validação e aprovação.

alter table public.preventiva_execucoes
  add column if not exists atraso_destinatarios jsonb not null default '[]'::jsonb,
  add column if not exists atraso_processando_em timestamptz;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'preventiva_execucoes_atraso_destinatarios_array_check'
       and conrelid = 'public.preventiva_execucoes'::regclass
  ) then
    alter table public.preventiva_execucoes
      add constraint preventiva_execucoes_atraso_destinatarios_array_check
      check (jsonb_typeof(atraso_destinatarios) = 'array');
  end if;
end
$$;
