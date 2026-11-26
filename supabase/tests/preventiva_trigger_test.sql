\set ON_ERROR_STOP on
create role anon;
create role authenticated;
create role service_role;
create schema if not exists private;
create table public.preventivas (
  id bigint primary key,
  ultima date,
  data_prevista date,
  intervalo_dias integer
);
create table public.os (
  id bigint primary key,
  preventiva_id bigint,
  status text,
  data_conclusao timestamptz,
  preventiva_atrasada boolean not null default false
);
create table public.preventiva_execucoes (
  id bigserial primary key,
  os_id bigint unique,
  status text,
  ultima_anterior date,
  data_prevista_anterior date,
  ultima_aplicada date,
  data_prevista_aplicada date,
  sincronizada_em timestamptz,
  atualizado_em timestamptz default now()
);
\i supabase/migrations/20261125200000_sincronizar_proxima_data_preventiva.sql

-- 1. Conclusão e reabertura sem ciclo posterior: restaura o snapshot.
insert into public.preventivas values (1, date '2026-01-01', date '2026-01-31', 30);
insert into public.os values (101, 1, 'Em Atendimento', timestamptz '2026-02-10 15:00:00+00', false);
insert into public.preventiva_execucoes (os_id,status) values (101,'aberta');
update public.os set status='Concluída' where id=101;
do $$ begin
  if (select ultima from public.preventivas where id=1) <> date '2026-02-10'
     or (select data_prevista from public.preventivas where id=1) <> date '2026-03-12'
  then raise exception 'Falha: conclusão não atualizou datas'; end if;
end $$;
update public.os set status='Em Atendimento' where id=101;
do $$ begin
  if (select ultima from public.preventivas where id=1) <> date '2026-01-01'
     or (select data_prevista from public.preventivas where id=1) <> date '2026-01-31'
  then raise exception 'Falha: reabertura não restaurou snapshot'; end if;
end $$;

-- 2. O.S. antiga reaberta depois de ciclo mais recente: não pode sobrescrever.
insert into public.os values (102, 1, 'Em Atendimento', timestamptz '2026-02-11 15:00:00+00', false);
insert into public.preventiva_execucoes (os_id,status) values (102,'aberta');
update public.os set status='Concluída' where id=102;
insert into public.os values (103, 1, 'Em Atendimento', timestamptz '2026-03-15 15:00:00+00', false);
insert into public.preventiva_execucoes (os_id,status) values (103,'aberta');
update public.os set status='Concluída' where id=103;
update public.os set status='Em Atendimento' where id=102;
do $$ begin
  if (select ultima from public.preventivas where id=1) <> date '2026-03-15'
     or (select data_prevista from public.preventivas where id=1) <> date '2026-04-14'
  then raise exception 'Falha: O.S. antiga sobrescreveu ciclo posterior'; end if;
end $$;

-- 3. Cancelamento antes da conclusão: não avança datas.
insert into public.preventivas values (2, date '2026-04-01', date '2026-05-01', 30);
insert into public.os values (201, 2, 'Aberta', null, false);
insert into public.preventiva_execucoes (os_id,status) values (201,'aberta');
update public.os set status='Cancelada' where id=201;
do $$ begin
  if (select ultima from public.preventivas where id=2) <> date '2026-04-01'
     or (select status from public.preventiva_execucoes where os_id=201) <> 'cancelada'
  then raise exception 'Falha: cancelamento antes da conclusão'; end if;
end $$;

-- 4. Sem execução rastreável: não altera datas.
insert into public.preventivas values (3, date '2026-05-01', date '2026-05-31', 30);
insert into public.os values (301, 3, 'Em Atendimento', timestamptz '2026-05-10 15:00:00+00', false);
update public.os set status='Concluída' where id=301;
do $$ begin
  if (select ultima from public.preventivas where id=3) <> date '2026-05-01'
     or (select data_prevista from public.preventivas where id=3) <> date '2026-05-31'
  then raise exception 'Falha: O.S. sem execução alterou preventiva'; end if;
end $$;

-- 5. Data de conclusão nula: usa a data local de São Paulo.
insert into public.preventivas values (4, date '2026-06-01', date '2026-07-01', 30);
insert into public.os values (401, 4, 'Aberta', null, false);
insert into public.preventiva_execucoes (os_id,status) values (401,'aberta');
update public.os set status='Concluída' where id=401;
do $$ begin
  if (select ultima from public.preventivas where id=4) is distinct from (now() at time zone 'America/Sao_Paulo')::date
  then raise exception 'Falha: fallback de data_conclusao nula'; end if;
end $$;

-- 6. Cancelar depois da conclusão restaura o snapshot quando ainda é o ciclo atual.
insert into public.preventivas values (5, date '2026-07-01', date '2026-07-31', 30);
insert into public.os values (501, 5, 'Em Atendimento', timestamptz '2026-07-10 15:00:00+00', false);
insert into public.preventiva_execucoes (os_id,status) values (501,'aberta');
update public.os set status='Concluída' where id=501;
update public.os set status='Cancelada' where id=501;
do $$ begin
  if (select ultima from public.preventivas where id=5) <> date '2026-07-01'
     or (select data_prevista from public.preventivas where id=5) <> date '2026-07-31'
     or (select status from public.preventiva_execucoes where os_id=501) <> 'cancelada'
  then raise exception 'Falha: cancelamento após conclusão não restaurou snapshot'; end if;
end $$;

-- 7. Intervalo nulo ou zero usa o padrão de 30 dias.
insert into public.preventivas values (6, date '2026-08-01', date '2026-08-31', 0);
insert into public.os values (601, 6, 'Em Atendimento', timestamptz '2026-08-10 15:00:00+00', false);
insert into public.preventiva_execucoes (os_id,status) values (601,'aberta');
update public.os set status='Concluída' where id=601;
do $$ begin
  if (select data_prevista from public.preventivas where id=6) <> date '2026-09-09'
  then raise exception 'Falha: intervalo zero não usou 30 dias'; end if;
end $$;

-- 8. Conversão para a data de São Paulo considera virada de dia local.
insert into public.preventivas values (7, date '2026-09-01', date '2026-10-01', 30);
insert into public.os values (701, 7, 'Em Atendimento', timestamptz '2026-09-10 02:30:00+00', false);
insert into public.preventiva_execucoes (os_id,status) values (701,'aberta');
update public.os set status='Concluída' where id=701;
do $$ begin
  if (select ultima from public.preventivas where id=7) <> date '2026-09-09'
     or (select data_prevista from public.preventivas where id=7) <> date '2026-10-09'
  then raise exception 'Falha: conversão de fuso horário de São Paulo'; end if;
end $$;
