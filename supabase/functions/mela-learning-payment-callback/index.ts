function exactAmountMinor(value: unknown): number | null {
    if (typeof value !== 'string' && typeof value !== 'number')
        return null;
    const match = /^(\d+)(?:\.(\d{1,2}))?$/.exec(String(value));
    if (!match)
        return null;
    const minor = Number(match[1]) * 100 + Number((match[2] || '').padEnd(2, '0'));
    return Number.isSafeInteger(minor) && minor > 0 ? minor : null;
}
function paymentEnvironment(p: any, key: string) {
    const configured = Deno.env.get('MELA_PAYMENT_MODE') === 'live' ? 'live' : 'test';
    if (p.mode !== configured || (configured === 'test') !== /TEST/i.test(key))
        throw Object.assign(new Error('Payment environment mismatch'), { status: 409 });
}
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'content-type, chapa-signature, x-chapa-signature', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: cors });
async function rest(path: string, init: RequestInit = {}) { const u = Deno.env.get('SUPABASE_URL')!, k = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; const h = new Headers(init.headers || {}); h.set('apikey', k); h.set('Authorization', `Bearer ${k}`); if (init.body)
    h.set('Content-Type', 'application/json'); const r = await fetch(`${u}/rest/v1/${path}`, { ...init, headers: h }); const tx = await r.text(); let d: any = null; try {
    d = tx ? JSON.parse(tx) : null;
}
catch {
    d = tx;
} if (!r.ok)
    throw Object.assign(new Error(typeof d === 'object' ? (d?.message || d?.hint || `Database ${r.status}`) : `Database ${r.status}`), { status: 500 }); return d; }
async function hmac(secret: string, msg: string) { const e = new TextEncoder(), key = await crypto.subtle.importKey('raw', e.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']); const sig = new Uint8Array(await crypto.subtle.sign('HMAC', key, e.encode(msg))); return Array.from(sig).map(x => x.toString(16).padStart(2, '0')).join(''); }
function equal(a: string, b: string) { if (a.length !== b.length)
    return false; let x = 0; for (let i = 0; i < a.length; i++)
    x |= a.charCodeAt(i) ^ b.charCodeAt(i); return x === 0; }
async function signature(req: Request, raw: string) { const sec = Deno.env.get('CHAPA_WEBHOOK_SECRET'); if (!sec)
    return { ok: false, reason: 'CHAPA_WEBHOOK_SECRET is not configured' }; const x = String(req.headers.get('x-chapa-signature') || '').trim().toLowerCase(), c = String(req.headers.get('chapa-signature') || '').trim().toLowerCase(), ex = await hmac(sec, raw); return { ok: !!((x && equal(x, ex)) || (c && equal(c, ex))), value: x || c, reason: 'Invalid Chapa webhook signature' }; }
async function log(sig: string, ref: string, payload: any) { return rest('rpc/log_chapa_webhook_event', { method: 'POST', body: JSON.stringify({ p_signature: sig, p_tx_ref: ref, p_payload: payload }) }); }
async function markAttemptPendingOrFailed(id: string, st: string, providerStatus: string, payload: any, failure: string | null, now: string) { const q = `mela_learning_payment_attempts?id=eq.${encodeURIComponent(id)}&status=in.(initiated,pending)`; return rest(q, { method: 'PATCH', body: JSON.stringify({ status: st, provider_status: providerStatus, verify_payload: payload, failure_reason: failure, last_verified_at: now, updated_at: now }) }); }
async function processRef(ref: string) { const p = (await rest(`mela_learning_payment_attempts?select=*&tx_ref=eq.${encodeURIComponent(ref)}&limit=1`))?.[0]; if (!p)
    return { state: 'not_found' }; if (p.status === 'success')
    return { state: 'success', already_verified: true }; if (!['initiated', 'pending'].includes(p.status))
    return { state: p.status }; const key = Deno.env.get('CHAPA_SECRET_KEY'); if (!key)
    throw Object.assign(new Error('Chapa secret is not configured.'), { status: 503 }); paymentEnvironment(p, key); const r = await fetch(`https://api.chapa.co/v1/transaction/verify/${encodeURIComponent(p.tx_ref)}`, { headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) }); const tx = await r.text(); let b: any = {}; try {
    b = tx ? JSON.parse(tx) : {};
}
catch { } const now = new Date().toISOString(); if (!r.ok || b?.status !== 'success' || typeof b?.data?.status !== 'string' || !b.data.status)
    throw Object.assign(new Error('Provider verification temporarily unavailable'), { status: 503 }); const d = b?.data || {}, ps = String(d.status || '').toLowerCase(); if (ps !== 'success') {
    const st = ps === 'failed' ? 'failed' : 'pending';
    await markAttemptPendingOrFailed(p.id, st, ps || st, b, st === 'failed' ? (b?.message || 'Payment failed') : null, now);
    return { state: st };
} const cents = exactAmountMinor(d.amount); const checks = { provider_reference: typeof (d.reference || d.ref_id) === 'string' && !!(d.reference || d.ref_id).trim(), tx_ref: String(d.tx_ref || '') === p.tx_ref, amount: cents !== null && cents === Number(p.expected_amount_minor), currency: p.expected_currency === 'ETB' && String(d.currency || '').toUpperCase() === p.expected_currency, mode: String(d.mode || '').toLowerCase() === String(p.mode || '').toLowerCase() }; if (!Object.values(checks).every(Boolean)) {
    await markAttemptPendingOrFailed(p.id, 'pending', ps, b, `Verification mismatch ${JSON.stringify(checks)}`, now);
    return { state: 'mismatch', checks };
} const out = await rest('rpc/finalize_mela_learning_payment', { method: 'POST', body: JSON.stringify({ p_payment_id: p.id, p_provider_ref: d.reference || d.ref_id || null, p_provider_method: d.method || null, p_provider_type: d.type || null, p_provider_charge: d.charge ?? null, p_verify_payload: b }) }); return { state: 'success', result: out }; }
Deno.serve(async (req) => { if (req.method === 'OPTIONS')
    return new Response('ok', { headers: cors }); if (req.method !== 'POST')
    return json({ error: 'Method not allowed' }, 405); try {
    const raw = await req.text(), sig = await signature(req, raw);
    if (!sig.ok)
        return json({ error: sig.reason }, sig.reason.includes('not configured') ? 503 : 401);
    let payload: any = {};
    try {
        payload = raw ? JSON.parse(raw) : {};
    }
    catch {
        return json({ error: 'Invalid JSON' }, 400);
    }
    const ref = String(payload?.tx_ref || payload?.trx_ref || payload?.data?.tx_ref || payload?.data?.trx_ref || '');
    if (!ref)
        return json({ error: 'Webhook did not include tx_ref' }, 400);
    await log(sig.value, ref, payload);
    const r = await processRef(ref);
    return json({ received: true, tx_ref: ref, status: r.state }, r.state === 'mismatch' ? 409 : 200);
}
catch (e: any) {
    console.error('mela-learning-payment-callback', e);
    return json({ error: e instanceof Error ? e.message : 'Unexpected error' }, e?.status || 500);
} });
