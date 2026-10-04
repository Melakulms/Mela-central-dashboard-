import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, chapa-signature, x-chapa-signature',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });

async function rest(path: string, init: RequestInit = {}) {
  const url = Deno.env.get('SUPABASE_URL');
  const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !secret) throw new Error('Database configuration unavailable');
  const requestHeaders = new Headers(init.headers);
  requestHeaders.set('apikey', secret);
  requestHeaders.set('Authorization', `Bearer ${secret}`);
  if (init.body) requestHeaders.set('Content-Type', 'application/json');
  const response = await fetch(`${url}/rest/v1/${path}`, { ...init, headers: requestHeaders });
  if (!response.ok) throw new Error(`Database request failed (${response.status})`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

async function hmac(secret: string, body: string) {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(body)));
  return Array.from(signature, value => value.toString(16).padStart(2, '0')).join('');
}
function equalSignature(actual: string, expected: string) {
  if (!/^[a-f0-9]{64}$/.test(actual) || actual.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < actual.length; i++) difference |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  return difference === 0;
}
function amountMinor(value: unknown): number | null {
  // Reject precision loss, exponent notation and coerced null/boolean values.
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
  if (!match) return null;
  const minor = Number(match[1]) * 100 + Number((match[2] || '').padEnd(2, '0'));
  return Number.isSafeInteger(minor) && minor > 0 ? minor : null;
}
async function updatePending(id: string, body: unknown) {
  // A slower callback must never downgrade a concurrently finalized payment.
  await rest(`escrow_payment_attempts?id=eq.${encodeURIComponent(id)}&status=in.(initiated,pending)`, {
    method: 'PATCH', body: JSON.stringify(body),
  });
}
async function verifyAttempt(attempt: any) {
  const mode = Deno.env.get('MELA_PAYMENT_MODE') === 'live' ? 'live' : 'test';
  const key = Deno.env.get('CHAPA_SECRET_KEY');
  if (!key || (mode === 'test') !== /TEST/i.test(key)) throw new Error('Payment key and mode configuration mismatch');
  if (attempt.mode !== mode) return { state: 'mode_mismatch' };
  const response = await fetch(`https://api.chapa.co/v1/transaction/verify/${encodeURIComponent(attempt.tx_ref)}`, {
    headers: { Authorization: `Bearer ${key}` },
    signal: AbortSignal.timeout(15000),
  });
  // Do not acknowledge transient provider failure as a successfully handled event.
  if (!response.ok) throw new Error(`Provider verification unavailable (${response.status})`);
  const payload = await response.json();
  const data = payload?.data || {};
  const status = String(data.status || '').toLowerCase();
  const now = new Date().toISOString();
  if (payload?.status !== 'success' || !status) throw new Error('Incomplete provider verification');
  if (status !== 'success') {
    const mapped = status === 'failed' ? 'failed' : 'pending';
    await updatePending(attempt.id, {
      status: mapped, provider_status: status, verify_payload: payload, last_verified_at: now,
      failure_reason: mapped === 'failed' ? 'Provider reported payment failure' : null,
    });
    return { state: mapped };
  }
  const minor = amountMinor(data.amount);
  const expected = Number(attempt.expected_amount_minor);
  const checks = {
    reference: typeof data.tx_ref === 'string' && data.tx_ref === attempt.tx_ref,
    amount: minor !== null && Number.isSafeInteger(expected) && minor === expected,
    currency: String(data.currency || '').toUpperCase() === String(attempt.currency || '').toUpperCase() && attempt.currency === 'ETB',
    mode: String(data.mode || '').toLowerCase() === attempt.mode,
    provider_reference: typeof (data.reference || data.ref_id) === 'string' && !!(data.reference || data.ref_id).trim(),
  };
  if (!Object.values(checks).every(Boolean)) {
    await updatePending(attempt.id, {
      provider_status: status, verify_payload: payload, last_verified_at: now,
      failure_reason: `Verification mismatch: ${JSON.stringify(checks)}`,
    });
    return { state: 'mismatch' };
  }
  const result = await rest('rpc/finalize_escrow_payment', {
    method: 'POST', body: JSON.stringify({
      p_payment_id: attempt.id, p_provider_ref: data.reference || data.ref_id,
      p_provider_method: data.method || null, p_provider_type: data.type || null,
      p_provider_charge: minor, p_verify_payload: payload,
    }),
  });
  if (result?.idempotent !== true) {
    // Notification failure must not replay the financial finalization.
    try {
      const escrow = (await rest(`escrow_transactions?id=eq.${encodeURIComponent(result?.escrow_id || attempt.escrow_id)}&select=id,user_id&limit=1`))?.[0];
      if (escrow) await rest('notifications', { method: 'POST', body: JSON.stringify({
        user_id: escrow.user_id, title: 'Escrow funded', body: 'The employer funded escrow for your freelance milestone.',
        ref_table: 'escrow_transactions', ref_id: escrow.id,
      }) });
    } catch { console.error('Escrow notification delivery failed'); }
  }
  return { state: 'success' };
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  try {
    const secret = Deno.env.get('CHAPA_WEBHOOK_SECRET');
    if (!secret) return json({ error: 'Webhook verification unavailable' }, 503);
    const raw = await request.text();
    if (new TextEncoder().encode(raw).length > 65536) return json({ error: 'Payload too large' }, 413);
    const expected = await hmac(secret, raw);
    // x-chapa-signature binds the standard webhook body. The custom Chapa
    // Signature webhook also signs the body in chapa-signature. A static
    // secret-only signature is intentionally insufficient here.
    const signatures = ['x-chapa-signature', 'chapa-signature'].map(name => (request.headers.get(name) || '').trim().toLowerCase());
    if (!signatures.some(signature => equalSignature(signature, expected))) return json({ error: 'Invalid webhook signature' }, 401);
    let payload: any;
    try { payload = JSON.parse(raw); } catch { return json({ error: 'Invalid JSON' }, 400); }
    const reference = payload?.tx_ref || payload?.trx_ref || payload?.data?.tx_ref || payload?.data?.trx_ref;
    if (typeof reference !== 'string' || !reference || reference.length > 256) return json({ error: 'Valid tx_ref required' }, 400);
    const attempt = (await rest(`escrow_payment_attempts?tx_ref=eq.${encodeURIComponent(reference)}&select=*&limit=1`))?.[0];
    if (!attempt) return json({ received: true, status: 'not_escrow' });
    if (attempt.status === 'success') return json({ received: true, status: 'success', already_verified: true });
    if (!['initiated', 'pending'].includes(attempt.status)) return json({ received: true, status: attempt.status });
    const result = await verifyAttempt(attempt);
    return json({ received: true, status: result.state }, ['mismatch', 'mode_mismatch'].includes(result.state) ? 409 : 200);
  } catch {
    console.error('Escrow callback verification unavailable');
    return json({ error: 'Verification temporarily unavailable; retry required' }, 503);
  }
});
