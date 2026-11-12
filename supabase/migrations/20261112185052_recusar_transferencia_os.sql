create or replace function public.erimax_recusar_transferencia_os(p_os_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_nome text;
  v_status text;
begin
  select p.nome into v_nome
  from public.perfis p
  where p.id = auth.uid()
    and (p.perfil = 'tecnico' or p.id = 'e978d5b1-9382-41de-be43-549a4e1e081e'::uuid);

  if v_nome is null then
    raise exception 'Somente o técnico destinatário pode recusar a transferência.';
  end if;

  select o.status into v_status
  from public.os o
  where o.id = p_os_id
    and o.transferencia_para = v_nome
  for update;

  if not found or v_status <> 'Em Atendimento' then
    raise exception 'Não existe uma transferência pendente para você nesta O.S.';
  end if;

  update public.os
  set transferencia_para = null,
      transferencia_solicitada_por = null,
      transferencia_solicitada_em = null,
      transferencia_motivo = null
  where id = p_os_id;
end;
$function$;

revoke all on function public.erimax_recusar_transferencia_os(bigint) from public;
revoke all on function public.erimax_recusar_transferencia_os(bigint) from anon;
grant execute on function public.erimax_recusar_transferencia_os(bigint) to authenticated;
