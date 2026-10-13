// Admin-only scope. Never cache credentials, API responses or dashboard records.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
  if (event.request.mode !== 'navigate' || !event.request.url.startsWith(self.registration.scope)) return;
  event.respondWith(fetch(event.request).catch(() => new Response(
    '<!doctype html><html lang="en"><meta name="viewport" content="width=device-width, initial-scale=1"><title>MELA Admin offline</title><h1>MELA Admin is offline</h1><p>Connect to the internet and reopen the app to sign in securely.</p></html>',
    { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } }
  )));
});
