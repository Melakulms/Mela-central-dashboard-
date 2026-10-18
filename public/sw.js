// Offline admin access is limited to this public help page. No account data is cached.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  const scope = new URL(self.registration.scope);
  if (event.request.method !== 'GET' || event.request.mode !== 'navigate' || url.origin !== scope.origin || !url.pathname.startsWith(scope.pathname)) return;
  event.respondWith(fetch(event.request).catch(() => new Response(
    '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MELA Admin offline guide</title><style>body{font:18px/1.6 system-ui;max-width:650px;margin:auto;padding:24px;background:#f2f5f8;color:#183044}a{color:#155e75}</style><h1>MELA Admin offline guide</h1><p>Administrative records and actions require an internet connection and verified sign-in.</p><h2>Prepare your review</h2><ul><li>Questions: check correctness, subject, grade, explanation and age suitability.</li><li>Lessons: check learning goals, examples, sources and practice tasks.</li><li>Reports: reconnect to inspect evidence and record a decision securely.</li></ul><p>No approvals or changes can be submitted here. Do not put personal information into offline notes on a shared device.</p><a href="./">Reconnect and sign in</a></html>',
    { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' } }
  )));
});
