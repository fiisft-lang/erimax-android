-- Estas RPCs exigem sessão autenticada; remover qualquer concessão direta a anon.
REVOKE ALL ON FUNCTION public.erimax_solicitar_transferencia_os(bigint, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.erimax_aceitar_transferencia_os(bigint) FROM anon;
