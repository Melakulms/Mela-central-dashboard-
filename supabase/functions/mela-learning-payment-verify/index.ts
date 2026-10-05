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
async function authenticatedIdentity(req: Request) {
    const authorization = req.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer '))
        throw Object.assign(new Error('Authentication required'), { status: 401 });
    const response = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, { headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY')!, Authorization: authorization } });
    if (!response.ok)
        throw Object.assign(new Error('Invalid session'), { status: 401 });
    const user = await response.json();
    if (typeof user.id !== 'string' || !user.id)
        throw Object.assign(new Error('Invalid session'), { status: 401 });
    return user.id;
}
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json', 'Cache-Control': 'no-store' };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: cors });
async function rest(path: string, init: RequestInit = {}) { const u = Deno.env.get('SUPABASE_URL')!, k = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; const h = new Headers(init.headers || {}); h.set('apikey', k); h.set('Authorization', `Bearer ${k}`); if (init.body)
    h.set('Content-Type', 'application/json'); const r = await fetch(`${u}/rest/v1/${path}`, { ...init, headers: h }); const tx = await r.text(); let d: any = null; try {
    d = tx ? JSON.parse(tx) : null;
}
catch {
    d = tx;
} if (!r.ok)
    throw Object.assign(new Error(typeof d === 'object' ? (d?.message || d?.hint || `Database ${r.status}`) : `Database ${r.status}`), { status: 500 }); return d; }
async function verifyProvider(p: any) {
    const key = Deno.env.get('CHAPA_SECRET_KEY');
    if (!key)
        throw Object.assign(new Error('Chapa test secret is not configured.'), { status: 503 });
    if (!/TEST/i.test(key))
        throw Object.assign(new Error('Pre-launch verifier accepts only a Chapa TEST secret.'), { status: 503 });
    paymentEnvironment(p, key);
    const r = await fetch(`https://api.chapa.co/v1/transaction/verify/${encodeURIComponent(p.tx_ref)}`, { headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) });
    const tx = await r.text();
    let b: any = {};
    try {
        b = tx ? JSON.parse(tx) : {};
    }
    catch { }
    const now = new Date().toISOString();
    if (!r.ok || b?.status !== 'success' || typeof b?.data?.status !== 'string' || !b.data.status)
        throw Object.assign(new Error('Provider verification temporarily unavailable'), { status: 503 });
    const d = b?.data || {}, ps = String(d.status || '').toLowerCase();
    if (ps !== 'success') {
        const st = ps === 'failed' ? 'failed' : 'pending';
        await rest(`mela_learning_payment_attempts?id=eq.${encodeURIComponent(p.id)}&status=in.(initiated,pending)`, { method: 'PATCH', body: JSON.stringify({ status: st, provider_status: ps || st, verify_payload: b, failure_reason: st === 'failed' ? (b?.message || 'Payment failed') : null, last_verified_at: now, updated_at: now }) });
        return { state: st };
    }
    const cents = exactAmountMinor(d.amount);
    const checks = { provider_reference: typeof (d.reference || d.ref_id) === 'string' && !!(d.reference || d.ref_id).trim(), tx_ref: String(d.tx_ref || '') === p.tx_ref, amount: cents !== null && cents === Number(p.expected_amount_minor), currency: p.expected_currency === 'ETB' && String(d.currency || '').toUpperCase() === p.expected_currency, mode: String(d.mode || '').toLowerCase() === String(p.mode || '').toLowerCase() };
    if (!Object.values(checks).every(Boolean)) {
        await rest(`mela_learning_payment_attempts?id=eq.${encodeURIComponent(p.id)}&status=in.(initiated,pending)`, { method: 'PATCH', body: JSON.stringify({ provider_status: ps, verify_payload: b, failure_reason: `Verification mismatch ${JSON.stringify(checks)}`, last_verified_at: now, updated_at: now }) });
        return { state: 'mismatch', checks };
    }
    const out = await rest('rpc/finalize_mela_learning_payment', { method: 'POST', body: JSON.stringify({ p_payment_id: p.id, p_provider_ref: d.reference || d.ref_id || null, p_provider_method: d.method || null, p_provider_type: d.type || null, p_provider_charge: cents, p_verify_payload: b }) });
    return { state: 'success', result: out };
}
Deno.serve(async (req) => { if (req.method === 'OPTIONS')
    return new Response('ok', { headers: cors }); if (req.method !== 'POST')
    return json({ error: 'Method not allowed' }, 405); try {
    const uid = await authenticatedIdentity(req);
    if (!uid)
        return json({ error: 'Invalid user session' }, 401);
    const body = await req.json().catch(() => ({})), ref = String(body?.tx_ref || '').trim();
    if (!ref)
        return json({ error: 'tx_ref is required' }, 400);
    const p = (await rest(`mela_learning_payment_attempts?select=*&tx_ref=eq.${encodeURIComponent(ref)}&user_id=eq.${uid}&limit=1`))?.[0];
    if (!p)
        return json({ error: 'Payment not found' }, 404);
    if (p.status === 'success')
        return json({ status: 'success', tx_ref: ref, entitlement_id: p.entitlement_id, already_verified: true });
    if (!['initiated', 'pending'].includes(p.status))
        return json({ status: p.status }, 409);
    const v = await verifyProvider(p);
    if (v.state === 'success')
        return json({ status: 'success', tx_ref: ref, result: v.result });
    if (v.state === 'pending')
        return json({ status: 'pending', tx_ref: ref }, 202);
    if (v.state === 'failed')
        return json({ status: 'failed', tx_ref: ref }, 402);
    if (v.state === 'mismatch')
        return json({ status: 'failed', code: 'VERIFICATION_MISMATCH', checks: v.checks }, 409);
    return json({ status: 'pending', tx_ref: ref }, 202);
}
catch (e: any) {
    console.error('mela-learning-payment-verify', e);
    return json({ error: e instanceof Error ? e.message : 'Unexpected error' }, e?.status || 500);
} });
