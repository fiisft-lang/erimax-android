-- EriMax: campos requeridos pelo código atual do APK.
-- Preparação somente: NÃO executar em produção antes de backup e revisão.
-- As alterações são aditivas e preservam os registros existentes.

alter table public.maquinas
  add column if not exists prefixo text;

create unique index if not exists maquinas_prefixo_unique
  on public.maquinas (prefixo)
  where prefixo is not null and btrim(prefixo) <> '';

alter table public.os
  add column if not exists ajustado_por text,
  add column if not exists ajustado_em timestamptz,
  add column if not exists ajuste_obs text;
