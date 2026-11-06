insert into public.status_tecnicos (
  user_id, status, turno_ativo, turno_inicio, os_atual_id, atualizado_em
)
select
  p.id,
  case when ativa.id is not null then 'EM SERVIÇO' else 'OFFLINE' end,
  (ativa.id is not null),
  ativa.data_atendimento,
  ativa.id,
  now()
from public.perfis p
left join lateral (
  select o.id, o.data_atendimento
  from public.os o
  where o.tecnico = p.nome and o.status = 'Em Atendimento'
  order by o.id desc
  limit 1
) ativa on true
where p.perfil = 'tecnico'
on conflict (user_id) do nothing;