-- Permite retomar apenas os destinatários que falharam no envio do lembrete.
-- Esta migration permanece na branch de testes; não aplicar em produção sem aprovação.

alter table public.preventiva_lembretes_enviados
  drop constraint if exists preventiva_lembretes_enviados_status_check;

alter table public.preventiva_lembretes_enviados
  add constraint preventiva_lembretes_enviados_status_check
  check (status in ('processando', 'parcial', 'enviado'));
