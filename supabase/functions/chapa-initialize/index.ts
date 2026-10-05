import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
};
const json = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers: cors });

async function rest(path: string, init: RequestInit = {}) {
  const url = Deno.env.get('SUPABASE_URL');
  const secret = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !secret) throw Object.assign(new Error('Database configuration unavailable'), { status: 503 });
  const headers = new Headers(init.headers || {});
  headers.set('apikey', secret);
  headers.set('Authorization', `Bearer ${secret}`);
  if (init.body) headers.set('Content-Type', 'application/json');
  const response = await fetch(`${url}/rest/v1/${path}`, { ...init, headers });
  const text = await response.text();
  let body: any = null;
  try { body = text ? JSON.parse(text) : null; } catch { body = text; }
  if (!response.ok && body?.code === '23505') throw Object.assign(new Error('An open checkout already exists. Verify it before retrying.'), { status: 409, code: 'CHECKOUT_PENDING' });
  if (!response.ok) throw Object.assign(new Error(typeof body === 'object' ? (body?.message || body?.hint || `Database ${response.status}`) : `Database ${response.status}`), { status: 500 });
  return body;
}
async function authenticatedIdentity(req: Request) {
  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) throw Object.assign(new Error('Authentication required'), { status: 401 });
  const response = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, {
    headers: { apikey: Deno.env.get('SUPABASE_ANON_KEY')!, Authorization: authorization },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw Object.assign(new Error('Invalid session'), { status: 401 });
  const user = await response.json();
  if (typeof user.id !== 'string' || !user.id || typeof user.email !== 'string' || !user.email) throw Object.assign(new Error('Authenticated user identity is incomplete'), { status: 401 });
  return { id: user.id as string, email: user.email as string };
}
async function featureAvailable(key: string) {
  return (await rest('rpc/platform_feature_available', { method: 'POST', body: JSON.stringify({ p_feature_key: key }) })) === true;
}
function paymentMode() { return Deno.env.get('MELA_PAYMENT_MODE') === 'live' ? 'live' : 'test'; }
function chapaKey() {
  const key = Deno.env.get('CHAPA_SECRET_KEY');
  if (!key) throw Object.assign(new Error('Chapa secret key is not configured.'), { status: 503, code: 'CHAPA_NOT_CONFIGURED' });
  const mode = paymentMode();
  if (mode === 'test' && !/TEST/i.test(key)) throw Object.assign(new Error('Test mode requires a Chapa TEST secret key.'), { status: 503, code: 'CHAPA_TEST_KEY_REQUIRED' });
  if (mode === 'live' && /TEST/i.test(key)) throw Object.assign(new Error('Live mode requires a Chapa live secret key.'), { status: 503, code: 'CHAPA_LIVE_KEY_REQUIRED' });
  return key;
}
function safeCheckout(value: unknown) { try { if (typeof value !== 'string') return false; const u=new URL(value); return u.protocol==='https:' && !u.username && !u.password; } catch { return false; } }
function positiveMinor(value: unknown) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  const amount = Number(value);
  return Number.isSafeInteger(amount) && amount > 0 ? amount : null;
}
async function patchUnfinished(id: string, body: Record<string, unknown>) {
  return rest(`payments?id=eq.${encodeURIComponent(id)}&status=eq.initiated`, {
    method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(body),
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  try {
    if (!(await featureAvailable('payments')) || !(await featureAvailable('academy'))) {
      return json({ code: 'FEATURE_DISABLED', error: 'Mela payments are temporarily disabled by the platform administrator.' }, 503);
    }
    const identity = await authenticatedIdentity(req);
    const body = await req.json().catch(() => ({}));
    const slug = String(body?.course_slug || '').trim();
    if (!slug) return json({ error: 'course_slug is required' }, 400);

    const courses = await rest(`courses?select=id,slug,title,price_cents,currency&slug=eq.${encodeURIComponent(slug)}&is_published=eq.true&limit=1`);
    const course = courses?.[0];
    if (!course) return json({ error: 'Course not found' }, 404);
    const amountMinor = positiveMinor(course.price_cents);
    const currency = String(course.currency || '').toUpperCase();
    if (amountMinor === null) return json({ error: 'This course is free and does not require payment.' }, 400);
    if (currency !== 'ETB') return json({ code: 'UNSUPPORTED_CURRENCY', error: 'Mela checkout currently supports ETB only.' }, 409);

    const enrollment = await rest(`course_enrollments?select=id&user_id=eq.${identity.id}&course_id=eq.${course.id}&limit=1`);
    if (enrollment?.length) return json({ code: 'ALREADY_ENROLLED', error: 'You are already enrolled in this course.' }, 409);

    const mode = paymentMode();
    const recent = await rest(`payments?select=tx_ref,status,checkout_url,mode,expected_amount_cents,expected_currency&user_id=eq.${identity.id}&course_id=eq.${course.id}&mode=eq.${mode}&status=in.(initiated,pending)&limit=1`);
    const reusable = (recent || []).find((row: any) => row.status === 'pending' && safeCheckout(row.checkout_url) && row.mode === mode && Number(row.expected_amount_cents) === amountMinor && row.expected_currency === currency);
    if (reusable) {
      return json({ checkout_url: reusable.checkout_url, tx_ref: reusable.tx_ref, mode, reused: true, course: { slug: course.slug, title: course.title, amount: (amountMinor / 100).toFixed(2), currency } });
    }
    if (recent?.length) return json({ code: 'CHECKOUT_PENDING', tx_ref: recent[0].tx_ref, error: 'A checkout is already being processed. Verify it before starting another.' }, 409);

    const profile = (await rest(`profiles?select=full_name&id=eq.${identity.id}&limit=1`))?.[0] || {};
    const fullName = String(profile.full_name || 'Mela Learner').trim();
    const parts = fullName.split(/\s+/).filter(Boolean);
    const firstName = parts[0] || 'Mela';
    const lastName = parts.slice(1).join(' ') || 'Learner';
    const key = chapaKey();
    const txRef = `mela_course_${mode}_${Date.now()}_${crypto.randomUUID().replaceAll('-', '').slice(0, 12)}`;
    const amount = (amountMinor / 100).toFixed(2);
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const callbackUrl = `${supabaseUrl}/functions/v1/chapa-callback`;
    const returnBase = (Deno.env.get('MELA_RETURN_URL') || `${supabaseUrl}/functions/v1/mela-payment-staging`).replace(/\/$/, '');
    const returnUrl = `${returnBase}?payment=return&tx_ref=${encodeURIComponent(txRef)}`;

    const inserted = await rest('payments?select=id', {
      method: 'POST', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ user_id: identity.id, course_id: course.id, mode, tx_ref: txRef, expected_amount_cents: amountMinor, expected_currency: currency, status: 'initiated' }),
    });
    const paymentId = inserted?.[0]?.id;
    if (!paymentId) throw Object.assign(new Error('Payment attempt could not be created'), { status: 500 });

    const providerResponse = await fetch('https://api.chapa.co/v1/transaction/initialize', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount, currency, email: identity.email, first_name: firstName, last_name: lastName, tx_ref: txRef, callback_url: callbackUrl, return_url: returnUrl, customization: { title: `Mela — ${course.title}`, description: 'Mela course enrollment' }, meta: { payment_reason: `Mela course enrollment for ${course.title}`, payment_mode: mode, hide_receipt: false } }),
      signal: AbortSignal.timeout(15000),
    });
    const text = await providerResponse.text();
    let provider: any = {};
    try { provider = text ? JSON.parse(text) : {}; } catch {}
    const checkoutUrl = provider?.data?.checkout_url;
    if (!providerResponse.ok || provider?.status !== 'success' || !safeCheckout(checkoutUrl)) {
      await patchUnfinished(paymentId, { failure_reason: provider?.message || `Chapa initialize failed (${providerResponse.status})` });
      return json({ code: 'CHAPA_INITIALIZE_FAILED', error: provider?.message || 'Unable to initialize Chapa checkout.' }, 502);
    }

    const updated = await patchUnfinished(paymentId, { status: 'pending', checkout_url: checkoutUrl, provider_status: provider?.status || 'success' });
    if (!updated?.length) {
      const latest = (await rest(`payments?id=eq.${encodeURIComponent(paymentId)}&select=status,checkout_url&limit=1`))?.[0];
      if (latest?.status !== 'pending' || !latest?.checkout_url) throw Object.assign(new Error('Payment state changed before checkout became available.'), { status: 409 });
    }
    return json({ checkout_url: checkoutUrl, tx_ref: txRef, mode, course: { slug: course.slug, title: course.title, amount, currency } });
  } catch (e: any) {
    console.error('chapa-initialize', e);
    return json({ code: e?.code, error: e instanceof Error ? e.message : 'Unexpected error' }, e?.status || 500);
  }
});
