-- EriMax: identidade única de máquina nas ordens e preventivas.
-- Preparada para revisão/aplicação controlada; NÃO executar em produção nesta etapa.
alter table public.os add column if not exists maquina_id bigint;
alter table public.preventivas add column if not exists maquinas_ids jsonb not null default '[]'::jsonb;
do $$
begin
 if not exists(select 1 from pg_constraint where conname='os_maquina_id_fkey' and conrelid='public.os'::regclass) then
  alter table public.os add constraint os_maquina_id_fkey foreign key(maquina_id) references public.maquinas(id) on update cascade on delete set null;
 end if;
end $$;
create index if not exists idx_os_maquina_id on public.os(maquina_id);
-- Backfill somente quando nome + setor identifica exatamente um cadastro.
-- Registros ambíguos (incluindo MESA/SELADORA SL-11 e SL-12) permanecem NULL.
update public.os o set maquina_id=(select min(m.id) from public.maquinas m where lower(trim(m.nome))=lower(trim(o.maquina)) and lower(trim(m.setor))=lower(trim(o.setor)) having count(*)=1)
where o.maquina_id is null and o.maquina is not null and o.maquina not ilike 'Outros — %'
and (select count(*) from public.maquinas m where lower(trim(m.nome))=lower(trim(o.maquina)) and lower(trim(m.setor))=lower(trim(o.setor)))=1;
