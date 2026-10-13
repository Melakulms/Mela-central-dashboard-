// Retired: the old profile-role-only API bypassed the Central Admin boundary.
// Keep a tombstone deployed so previously published clients cannot revive it.
Deno.serve(() => new Response(JSON.stringify({
  error: 'This legacy administrator endpoint is retired. Use MELA Central Admin.',
  code: 'LEGACY_ENDPOINT_RETIRED',
}), {
  status: 410,
  headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' },
}));
