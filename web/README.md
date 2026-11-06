# EriMax Web — preparação de alinhamento com o APK

O frontend de referência está em `../index.html`. O APK usa o Supabase principal configurado nesse código.

## Estado
- Branch de trabalho: `web-alignment-staging`.
- Nenhuma alteração foi feita no Cloudflare Pages nem no banco Supabase.
- O código atual do APK contém chamadas aos campos `maquinas.prefixo` e `os.ajustado_por`, `os.ajustado_em`, `os.ajuste_obs`; esses campos não existem no schema atual do banco principal.
- A migração proposta está em `../supabase/migrations/20261106_web_alignment_fields.sql` e não foi aplicada.
- Push FCM nativo depende do Capacitor/Android. O navegador recebe Realtime em primeiro plano; push web com navegador fechado exige configuração própria de Web Push/FCM Web.

## Antes de publicar
1. Fazer backup independente dos dados Supabase e do deployment Pages.
2. Revisar schema, RLS e armazenamento de fotos.
3. Adaptar e testar o frontend em ambiente de homologação.
4. Configurar notificações web, se necessário.
5. Publicar somente após testes funcionais.
