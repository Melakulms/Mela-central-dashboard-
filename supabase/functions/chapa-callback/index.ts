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
function eq(a: string, b: string) { if (a.length !== b.length)
    return false; let x = 0; for (let i = 0; i < a.length; i++)
    x |= a.charCodeAt(i) ^ b.charCodeAt(i); return x === 0; }
async function verifyEventSignature(req: Request, raw: string) { const sec = Deno.env.get('CHAPA_WEBHOOK_SECRET'); if (!sec)
    return { ok: false, reason: 'CHAPA_WEBHOOK_SECRET is not configured' }; const supplied = (req.headers.get('x-chapa-signature') || req.headers.get('chapa-signature') || '').trim().toLowerCase(); if (!supplied)
    return { ok: false, reason: 'Missing Chapa webhook signature' }; const expected = await hmac(sec, raw); return { ok: eq(supplied, expected), signature: supplied, reason: 'Invalid Chapa webhook signature' }; }
async function verifyPayment(p: any) { const key = Deno.env.get('CHAPA_SECRET_KEY'); if (!key)
    throw Object.assign(new Error('Chapa secret is not configured on the server.'), { status: 503 }); paymentEnvironment(p, key); const r = await fetch(`https://api.chapa.co/v1/transaction/verify/${encodeURIComponent(p.tx_ref)}`, { headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) }); const tx = await r.text(); let b: any = {}; try {
    b = tx ? JSON.parse(tx) : {};
}
catch { } const now = new Date().toISOString(); if (!r.ok || b?.status !== 'success' || typeof b?.data?.status !== 'string' || !b.data.status)
    throw Object.assign(new Error('Provider verification temporarily unavailable'), { status: 503 }); const d = b?.data || {}, ps = String(d.status || '').toLowerCase(); if (ps !== 'success') {
    const mapped = ps === 'failed' ? 'failed' : 'pending';
    await rest(`payments?id=eq.${encodeURIComponent(p.id)}&status=in.(initiated,pending)`, { method: 'PATCH', body: JSON.stringify({ status: mapped, provider_status: ps || mapped, verify_payload: b, failure_reason: mapped === 'failed' ? (b?.message || 'Payment failed') : null, last_verified_at: now }) });
    return { state: mapped };
} const cents = exactAmountMinor(d.amount); const checks = { provider_reference: typeof (d.reference || d.ref_id) === 'string' && !!(d.reference || d.ref_id).trim(), mode: String(d.mode || '').toLowerCase() === p.mode, tx_ref: String(d.tx_ref || '') === p.tx_ref, amount: cents !== null && cents === Number(p.expected_amount_cents), currency: p.expected_currency === 'ETB' && String(d.currency || '').toUpperCase() === p.expected_currency }; if (!Object.values(checks).every(Boolean)) {
    await rest(`payments?id=eq.${encodeURIComponent(p.id)}&status=in.(initiated,pending)`, { method: 'PATCH', body: JSON.stringify({ provider_status: ps, verify_payload: b, failure_reason: `Verification mismatch: ${JSON.stringify(checks)}`, last_verified_at: now }) });
    return { state: 'mismatch', checks };
} const updated = await rest(`payments?id=eq.${encodeURIComponent(p.id)}&status=in.(initiated,pending)`, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify({ status: 'success', provider_status: ps, provider_ref: d.reference || d.ref_id || null, provider_method: d.method || null, provider_type: d.type || null, provider_charge: d.charge ?? null, verify_payload: b, failure_reason: null, paid_at: p.paid_at || now, last_verified_at: now }) }); if (!updated?.length) {
    const latest = (await rest(`payments?id=eq.${encodeURIComponent(p.id)}&select=status&limit=1`))?.[0];
    if (latest?.status !== 'success')
        throw Object.assign(new Error('Payment state changed; verify again'), { status: 409 });
} return { state: 'success' }; }
async function processRef(ref: string) { if (!ref)
    return { state: 'missing' }; const rows = await rest(`payments?select=*&tx_ref=eq.${encodeURIComponent(ref)}&limit=1`); const p = rows?.[0]; if (!p)
    return { state: 'not_found' }; if (p.status === 'success')
    return { state: 'success', already_verified: true }; if (!['initiated', 'pending'].includes(p.status))
    return { state: p.status }; return verifyPayment(p); }
Deno.serve(async (req) => { if (req.method === 'OPTIONS')
    return new Response('ok', { headers: cors }); if (req.method !== 'POST')
    return json({ error: 'Method not allowed' }, 405); try {
    const raw = await req.text(), sig = await verifyEventSignature(req, raw);
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
    const result = await processRef(ref);
    return json({ received: true, tx_ref: ref, status: result.state }, result.state === 'mismatch' ? 409 : 200);
}
catch (e: any) {
    return json({ error: e instanceof Error ? e.message : 'Unexpected error' }, e?.status || 500);
} });
