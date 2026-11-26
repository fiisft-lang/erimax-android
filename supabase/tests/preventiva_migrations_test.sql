\set ON_ERROR_STOP on

do $role$ begin create role anon; exception when duplicate_object then null; end $role$;
do $role$ begin create role authenticated; exception when duplicate_object then null; end $role$;
do $role$ begin create role service_role; exception when duplicate_object then null; end $role$;

create schema auth;
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table public.preventivas (
  id bigserial primary key,
  setor text not null,
  maquina text not null,
  descricao text not null,
  intervalo_dias integer not null default 30,
  ultima date not null default current_date,
  data_prevista date,
  tecnico_responsavel text,
  maquinas jsonb not null default '[]'::jsonb,
  tecnicos_participantes jsonb not null default '[]'::jsonb,
  maquinas_ids bigint[] not null default '{}'
);

create table public.perfis (
  id uuid primary key,
  nome text not null,
  perfil text not null
);

create table public.os (
  id bigserial primary key,
  preventiva_id bigint references public.preventivas(id),
  tipo text,
  status text,
  tecnico text,
  tecnicos_participantes jsonb not null default '[]'::jsonb,
  maquinas_execucao jsonb not null default '[]'::jsonb,
  data_conclusao timestamptz,
  created_at timestamptz not null default now(),
  numero_mes integer,
  setor text,
  maquina text,
  maquina_id bigint,
  turno text,
  prioridade text,
  descricao text
);

\i supabase/migrations/20261125170000_automacao_preventivas_execucoes.sql
\i supabase/migrations/20261125183000_permitir_baixa_equipe_preventiva.sql
\i supabase/migrations/20261125190000_retentativa_lembretes_preventiva.sql
\i supabase/migrations/20261125191000_retentativa_alerta_atraso_gestores.sql
\i supabase/migrations/20261125200000_sincronizar_proxima_data_preventiva.sql
\i supabase/migrations/20261126180000_configuracao_alarmas_preventivas.sql

insert into public.preventivas
  (id,setor,maquina,descricao,intervalo_dias,ultima,data_prevista,tecnico_responsavel,maquinas,tecnicos_participantes,maquinas_ids)
values
  (1,'Corte','Máquina 1','Inspeção e lubrificação',30,date '2026-10-27',date '2026-11-26','Ana',
   '["Máquina 1"]'::jsonb,'["Ana","Fii"]'::jsonb,array[10]::bigint[]);

do $
begin
  if (select horarios_disparo from public.preventivas where id=1) <> array['08:00','12:00','16:00']::text[]
     or (select alarme_ativo from public.preventivas where id=1) is not true then
    raise exception 'Falha: preventiva existente não recebeu configuração padrão dos alarmes';
  end if;
end
$;

insert into public.perfis (id,nome,perfil) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Ana','tecnico'),
  ('e978d5b1-9382-41de-be43-549a4e1e081e','Fii','gestor'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Outro gestor','gestor');

insert into public.os
  (id,preventiva_id,tipo,status,tecnico,tecnicos_participantes,maquinas_execucao,data_conclusao)
values
  (1,1,'Preventiva','Em Atendimento','Ana','["Ana","Fii"]'::jsonb,
   '[{"maquina_id":10,"nome":"Máquina 1","prefixo":"A","concluida":false,"concluida_em":null}]'::jsonb,
   null);

insert into public.preventiva_execucoes
  (preventiva_id,data_vencimento,data_geracao,os_id,prazo_em,status)
values
  (1,date '2026-11-26',date '2026-11-26',1,timestamptz '2026-11-28 23:59:59-03','aberta');

-- Fii é gestor no cadastro, mas possui dupla função técnico/gestor e integra a equipe.
set role authenticated;
select set_config('request.jwt.claim.sub','e978d5b1-9382-41de-be43-549a4e1e081e',false);
select public.erimax_salvar_progresso_preventiva(
  1,
  '[{"maquina_id":10,"nome":"Máquina 1","prefixo":"A","concluida":true,"concluida_em":"2026-11-26T10:00:00-03:00"}]'::jsonb
);
reset role;

do $$
begin
  if (select maquinas_execucao -> 0 ->> 'concluida' from public.os where id=1) <> 'true' then
    raise exception 'Falha: integrante gestor com dupla função não conseguiu registrar máquina';
  end if;
end
$$;

-- A equipe pode alterar somente os campos de conclusão, nunca a identidade da máquina.
set role authenticated;
select set_config('request.jwt.claim.sub','e978d5b1-9382-41de-be43-549a4e1e081e',false);
do $$
begin
  begin
    perform public.erimax_salvar_progresso_preventiva(
      1,
      '[{"maquina_id":999,"nome":"Máquina 1","prefixo":"A","concluida":true,"concluida_em":"2026-11-26T10:00:00-03:00"}]'::jsonb
    );
    raise exception 'O teste deveria rejeitar alteração da identidade da máquina';
  exception when others then
    if sqlerrm = 'O teste deveria rejeitar alteração da identidade da máquina' then
      raise;
    end if;
  end;
end
$$;
reset role;

-- Outros gestores não podem registrar andamento se não forem técnico/equipe.
set role authenticated;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',false);
do $$
begin
  begin
    perform public.erimax_salvar_progresso_preventiva(
      1,
      '[{"maquina_id":10,"nome":"Máquina 1","prefixo":"A","concluida":true,"concluida_em":"2026-11-26T10:00:00-03:00"}]'::jsonb
    );
    raise exception 'O teste deveria rejeitar gestor sem função técnica';
  exception when others then
    if sqlerrm = 'O teste deveria rejeitar gestor sem função técnica' then
      raise;
    end if;
  end;
end
$$;
reset role;

-- Concluir a O.S. atualiza a data da preventiva; reabrir restaura o snapshot anterior.
update public.os
   set status='Concluída',
       data_conclusao=timestamptz '2026-11-26 13:00:00-03'
 where id=1;

do $$
begin
  if (select ultima from public.preventivas where id=1) <> date '2026-11-26'
     or (select data_prevista from public.preventivas where id=1) <> date '2026-12-26' then
    raise exception 'Falha: conclusão não sincronizou as datas da preventiva';
  end if;
end
$$;

update public.os set status='Em Atendimento' where id=1;

do $$
begin
  if (select ultima from public.preventivas where id=1) <> date '2026-10-27'
     or (select data_prevista from public.preventivas where id=1) <> date '2026-11-26' then
    raise exception 'Falha: reabertura não restaurou o snapshot da preventiva';
  end if;
end
$$;
