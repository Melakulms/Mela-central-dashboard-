// Retired: this maintenance worker used a hard-coded credential and followed
// unchecked redirects. Do not restore it without authenticated, SSRF-safe fetching.
Deno.serve(() => new Response(JSON.stringify({
  error: 'This legacy source recheck endpoint is retired.',
  code: 'LEGACY_ENDPOINT_RETIRED',
}), {
  status: 410,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
}));
