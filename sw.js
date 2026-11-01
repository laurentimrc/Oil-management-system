// Service worker di Il mio Uliveto: riceve le notifiche push e apre l'app nella sezione giusta.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));

self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { titolo: 'Il mio Uliveto', testo: e.data && e.data.text() }; }
  e.waitUntil(self.registration.showNotification(d.titolo || 'Il mio Uliveto', {
    body: d.testo || '',
    icon: 'icon-192.png',
    badge: 'icon-192.png',
    tag: d.tag || undefined,
    data: { url: d.url || './' },
    lang: 'it'
  }));
});

self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL(e.notification.data && e.notification.data.url || './', self.registration.scope).href;
  e.waitUntil((async () => {
    const tutte = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of tutte) {
      if (c.url.startsWith(self.registration.scope)) { await c.focus(); return c.navigate(url).catch(() => null); }
    }
    return self.clients.openWindow(url);
  })());
});
