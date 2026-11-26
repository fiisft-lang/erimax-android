-- A rotina de lembretes usa "parcial" quando ao menos um destinatário ainda
-- precisa receber a notificação. Alinhar a restrição do banco com esse estado.

alter table public.preventiva_lembretes_enviados
  drop constraint if exists preventiva_lembretes_enviados_status_check;

alter table public.preventiva_lembretes_enviados
  add constraint preventiva_lembretes_enviados_status_check
  check (status in ('processando', 'parcial', 'enviado'));
