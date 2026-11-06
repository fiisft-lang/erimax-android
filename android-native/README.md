# Alerta de nova O.S. — staging

Implementação nativa experimental para Capacitor 7. O workflow copia as classes Java para o projeto Android gerado e registra o serviço substituto do MessagingService do plugin.

O payload FCM para O.S. deve ser data-only e conter os campos `os_id`, `maquina`, `setor` e `numero`. A tela nativa abre a URI `erimax://os/{id}`; o listener do Capacitor App encaminha a O.S. para o painel.

A notificação em tela cheia é solicitada pelo Android, mas pode ser rebaixada para heads-up conforme versão, permissões e políticas do dispositivo. O botão Silenciar cancela somente a notificação local deste aparelho.
