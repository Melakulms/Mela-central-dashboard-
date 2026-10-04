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
function json(data: unknown, status = 200) { return new Response(JSON.stringify(data), { status, headers: cors }); }
async function rest(path: string, init: RequestInit = {}) { const u = Deno.env.get('SUPABASE_URL')!, s = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; const h = new Headers(init.headers || {}); h.set('apikey', s); h.set('Authorization', `Bearer ${s}`); if (init.body)
    h.set('Content-Type', 'application/json'); const r = await fetch(`${u}/rest/v1/${path}`, { ...init, headers: h }); const tx = await r.text(); let d: any = null; try {
    d = tx ? JSON.parse(tx) : null;
}
catch {
    d = tx;
} if (!r.ok)
    throw new Error(typeof d === 'object' ? (d?.message || d?.hint || `Database error ${r.status}`) : `Database error ${r.status}`); return d; }
async function updatePayment(id: string, body: any) { return rest(`payments?id=eq.${encodeURIComponent(id)}&status=in.(initiated,pending)`, { method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(body) }); }
async function ensureEnrollment(p: any) { return rest('course_enrollments', { method: 'POST', headers: { Prefer: 'resolution=ignore-duplicates,return=minimal' }, body: JSON.stringify({ user_id: p.user_id, course_id: p.course_id }) }); }
async function verifyWithChapa(p: any) {
    const key = Deno.env.get('CHAPA_SECRET_KEY');
    if (!key)
        throw Object.assign(new Error('Chapa test secret is not configured on the server.'), { code: 'CHAPA_NOT_CONFIGURED', status: 503 });
    if (!/TEST/i.test(key))
        throw Object.assign(new Error('This staging endpoint accepts only a Chapa TEST secret key.'), { code: 'CHAPA_TEST_KEY_REQUIRED', status: 503 });
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
    const d = b?.data || {};
    const providerStatus = String(d.status || '').toLowerCase();
    if (providerStatus !== 'success') {
        const mapped = providerStatus === 'failed' ? 'failed' : 'pending';
        await updatePayment(p.id, { status: mapped, provider_status: providerStatus || mapped, verify_payload: b, failure_reason: mapped === 'failed' ? (b?.message || 'Payment failed') : null, last_verified_at: now });
        return { state: mapped };
    }
    const cents = exactAmountMinor(d.amount);
    const checks = { provider_reference: typeof (d.reference || d.ref_id) === 'string' && !!(d.reference || d.ref_id).trim(), tx_ref: String(d.tx_ref || '') === p.tx_ref, amount: cents !== null && cents === Number(p.expected_amount_cents), currency: p.expected_currency === 'ETB' && String(d.currency || '').toUpperCase() === p.expected_currency, mode: p.mode === 'test' && String(d.mode || '').toLowerCase() === p.mode };
    if (!Object.values(checks).every(Boolean)) {
        await updatePayment(p.id, { provider_status: providerStatus, verify_payload: b, failure_reason: `Verification mismatch: ${JSON.stringify(checks)}`, last_verified_at: now });
        return { state: 'mismatch', checks };
    }
    const updated = await updatePayment(p.id, { status: 'success', provider_status: providerStatus, provider_ref: d.reference || d.ref_id || null, provider_method: d.method || null, provider_type: d.type || null, provider_charge: d.charge ?? null, verify_payload: b, failure_reason: null, paid_at: p.paid_at || now, last_verified_at: now });
    if (!updated?.length) {
        const latest = (await rest(`payments?id=eq.${encodeURIComponent(p.id)}&select=status&limit=1`))?.[0];
        if (latest?.status !== 'success')
            throw Object.assign(new Error('Payment state changed; verify again'), { status: 409 });
    }
    await ensureEnrollment(p);
    return { state: 'success' };
}
Deno.serve(async (req) => { if (req.method === 'OPTIONS')
    return new Response('ok', { headers: cors }); if (req.method !== 'POST')
    return json({ error: 'Method not allowed' }, 405); try {
    const uid = await authenticatedIdentity(req);
    if (!uid)
        return json({ error: 'Invalid user session' }, 401);
    const body = await req.json().catch(() => ({}));
    const ref = String(body?.tx_ref || '').trim();
    if (!ref)
        return json({ error: 'tx_ref is required' }, 400);
    const rows = await rest(`payments?select=*&tx_ref=eq.${encodeURIComponent(ref)}&user_id=eq.${uid}&limit=1`);
    const p = rows?.[0];
    if (!p)
        return json({ error: 'Payment not found' }, 404);
    if (p.status === 'success') {
        await ensureEnrollment(p);
        return json({ status: 'success', tx_ref: p.tx_ref, already_verified: true });
    }
    if (!['initiated', 'pending'].includes(p.status))
        return json({ status: p.status }, 409);
    const result = await verifyWithChapa(p);
    if (result.state === 'success')
        return json({ status: 'success', tx_ref: p.tx_ref });
    if (result.state === 'pending')
        return json({ status: 'pending', tx_ref: p.tx_ref }, 202);
    if (result.state === 'failed')
        return json({ status: 'failed', tx_ref: p.tx_ref }, 402);
    if (result.state === 'mismatch')
        return json({ status: 'failed', code: 'VERIFICATION_MISMATCH', checks: result.checks }, 409);
    return json({ status: 'pending', tx_ref: p.tx_ref }, 202);
}
catch (e: any) {
    console.error('chapa-verify', e);
    return json({ code: e?.code, error: e instanceof Error ? e.message : 'Unexpected error' }, e?.status || 500);
} });
