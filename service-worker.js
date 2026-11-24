/* EriMax Web Push — service worker servido na raiz para permitir o escopo /. */
self.addEventListener('push', event => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = { body: event.data ? event.data.text() : '' };
  }
  const title = String(payload.title || 'Notificação EriMax');
  const options = {
    body: String(payload.body || 'Você recebeu uma nova atualização.'),
    tag: String(payload.tag || 'erimax-notificacao'),
    data: { url: String(payload.url || '/') },
    renotify: Boolean(payload.renotify),
    requireInteraction: true
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const rawUrl = event.notification && event.notification.data
    ? event.notification.data.url
    : '/';
  let target;
  try {
    target = new URL(rawUrl || '/', self.location.origin);
    if (target.origin !== self.location.origin) target = new URL('/', self.location.origin);
  } catch (_) {
    target = new URL('/', self.location.origin);
  }
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if (client.url.startsWith(self.location.origin) && 'focus' in client) {
        if ('navigate' in client) await client.navigate(target.href);
        return client.focus();
      }
    }
    if (self.clients.openWindow) return self.clients.openWindow(target.href);
  })());
});

self.addEventListener('notificationclose', () => {});
