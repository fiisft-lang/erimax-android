self.addEventListener('install', event => { self.skipWaiting(); });
self.addEventListener('activate', event => { event.waitUntil(self.clients.claim()); });
self.addEventListener('push', event => {
  let payload = {};
  try { payload = event.data ? event.data.json() : {}; } catch (_) {}
  const title = payload.title || 'Nova ordem de serviço';
  const options = {
    body: payload.body || 'Uma nova O.S. aguarda a manutenção.',
    icon: '/erimax-pwa.svg',
    badge: '/erimax-pwa.svg',
    tag: payload.tag || ('erimax-os-' + (payload.os_id || Date.now())),
    renotify: true,
    data: { url: payload.url || '/index.html', os_id: payload.os_id || null }
  };
  event.waitUntil(self.registration.showNotification(title, options));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const data = event.notification.data || {};
  const target = new URL(data.url || '/index.html', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if ('focus' in client) {
        await client.focus();
        client.postMessage({ type: 'ERIMAX_OPEN_OS', os_id: data.os_id });
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});