-- Permite nomes repetidos de máquinas; o código identifica cada equipamento.
alter table public.maquinas drop constraint if exists maquinas_setor_nome_key;
create index if not exists maquinas_setor_nome_idx on public.maquinas (setor, nome);
drop index if exists public.maquinas_prefixo_unico_idx;
create unique index maquinas_prefixo_unico_idx
  on public.maquinas (regexp_replace(upper(btrim(prefixo)), '[^A-Z0-9]', '', 'g'))
  where prefixo is not null and btrim(prefixo) <> '';

-- Horário recorrente: cada turno pode ter um horário diferente em cada dia da semana.
create table if not exists public.setores_horarios_semanais (
  setor text not null,
  numero_turno smallint not null check (numero_turno between 1 and 3),
  dia_semana smallint not null check (dia_semana between 0 and 6),
  hora_inicio time not null default '08:00',
  hora_fim time not null default '17:00',
  ativo boolean not null default true,
  primary key (setor, numero_turno, dia_semana)
);

-- Exceção de uma data específica. Um array vazio significa que o setor não trabalhou naquele dia.
create table if not exists public.setores_horarios_excecoes (
  setor text not null,
  data_excecao date not null,
  observacao text not null default '',
  horarios jsonb not null default '[]'::jsonb check (jsonb_typeof(horarios) = 'array'),
  primary key (setor, data_excecao)
);

-- Migra os horários atuais para a nova grade semanal sem perder os turnos já cadastrados.
insert into public.setores_horarios_semanais (setor, numero_turno, dia_semana, hora_inicio, hora_fim, ativo)
select t.setor, t.numero_turno, split.dia::smallint, t.hora_inicio, t.hora_fim, true
from public.setores_turnos t
cross join lateral regexp_split_to_table(coalesce(t.dias,''), '') as split(dia)
where t.ativo = true and split.dia ~ '^[0-6]$'
on conflict (setor, numero_turno, dia_semana)
do update set hora_inicio=excluded.hora_inicio, hora_fim=excluded.hora_fim, ativo=true;

alter table public.setores_horarios_semanais enable row level security;
alter table public.setores_horarios_excecoes enable row level security;

drop policy if exists setores_horarios_semanais_select on public.setores_horarios_semanais;
create policy setores_horarios_semanais_select on public.setores_horarios_semanais
for select to authenticated using (true);
drop policy if exists setores_horarios_semanais_insert on public.setores_horarios_semanais;
create policy setores_horarios_semanais_insert on public.setores_horarios_semanais
for insert to authenticated with check (erimax_usuario_e_gestor());
drop policy if exists setores_horarios_semanais_update on public.setores_horarios_semanais;
create policy setores_horarios_semanais_update on public.setores_horarios_semanais
for update to authenticated using (erimax_usuario_e_gestor()) with check (erimax_usuario_e_gestor());
drop policy if exists setores_horarios_semanais_delete on public.setores_horarios_semanais;
create policy setores_horarios_semanais_delete on public.setores_horarios_semanais
for delete to authenticated using (erimax_usuario_e_gestor());

drop policy if exists setores_horarios_excecoes_select on public.setores_horarios_excecoes;
create policy setores_horarios_excecoes_select on public.setores_horarios_excecoes
for select to authenticated using (true);
drop policy if exists setores_horarios_excecoes_insert on public.setores_horarios_excecoes;
create policy setores_horarios_excecoes_insert on public.setores_horarios_excecoes
for insert to authenticated with check (erimax_usuario_e_gestor());
drop policy if exists setores_horarios_excecoes_update on public.setores_horarios_excecoes;
create policy setores_horarios_excecoes_update on public.setores_horarios_excecoes
for update to authenticated using (erimax_usuario_e_gestor()) with check (erimax_usuario_e_gestor());
drop policy if exists setores_horarios_excecoes_delete on public.setores_horarios_excecoes;
create policy setores_horarios_excecoes_delete on public.setores_horarios_excecoes
for delete to authenticated using (erimax_usuario_e_gestor());

grant select, insert, update, delete on public.setores_horarios_semanais to authenticated;
grant select, insert, update, delete on public.setores_horarios_excecoes to authenticated;
