-- Configuração individual dos alarmes de cada preventiva.
-- Os horários são avaliados pelo agendador; o ciclo de datas continua centralizado
-- em notificationStart(): segunda-quarta, quinta-sábado e domingo para segunda.

alter table public.preventivas
  add column if not exists horarios_disparo text[] not null
    default array['08:00', '12:00', '16:00']::text[],
  add column if not exists alarme_ativo boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.preventivas'::regclass
       and conname = 'preventivas_horarios_disparo_quantidade_check'
  ) then
    alter table public.preventivas
      add constraint preventivas_horarios_disparo_quantidade_check
      check (cardinality(horarios_disparo) between 1 and 12);
  end if;
end;
$$;
