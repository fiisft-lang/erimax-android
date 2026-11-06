alter table public.maquinas
  add column if not exists prefixo text;

create unique index if not exists maquinas_prefixo_unico_idx
  on public.maquinas (upper(btrim(prefixo)))
  where prefixo is not null and btrim(prefixo) <> '';