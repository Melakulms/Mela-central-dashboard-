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
  if (!response.ok) {
    throw Object.assign(new Error(typeof body === 'object' ? (body?.message || body?.hint || `Database ${response.status}`) : `Database ${response.status}`), { status: 500 });
  }
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
  if (typeof user.id !== 'string' || !user.id || typeof user.email !== 'string' || !user.email) {
    throw Object.assign(new Error('Authenticated user identity is incomplete'), { status: 401 });
  }
  return { id: user.id as string, email: user.email as string };
}

async function feature(key: string) {
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
  return rest(`mela_learning_payment_attempts?id=eq.${encodeURIComponent(id)}&status=eq.initiated`, {
    method: 'PATCH', headers: { Prefer: 'return=representation' }, body: JSON.stringify(body),
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  try {
    if (!(await feature('payments'))) return json({ code: 'PAYMENTS_DISABLED', error: 'Mela subscription checkout is not enabled yet.' }, 503);

    const identity = await authenticatedIdentity(req);
    const body = await req.json().catch(() => ({}));
    const productKey = String(body?.product_key || '').trim();
    if (!productKey) return json({ error: 'product_key is required' }, 400);

    const products = await rest(`mela_learning_products?select=*&product_key=eq.${encodeURIComponent(productKey)}&active=eq.true&limit=1`);
    const product = products?.[0];
    if (!product) return json({ error: 'Learning product not found' }, 404);
    const amountMinor = positiveMinor(product.active_price_minor);
    const currency = String(product.currency || '').toUpperCase();
    if (!product.sale_enabled || amountMinor === null) return json({ code: 'NOT_FOR_SALE', error: 'This learning product is not enabled for checkout.' }, 409);
    if (currency !== 'ETB') return json({ code: 'UNSUPPORTED_CURRENCY', error: 'Mela checkout currently supports ETB only.' }, 409);
    if (!['subscription', 'one_time'].includes(String(product.product_type))) return json({ error: 'Product type is not eligible for public checkout' }, 400);

    const profile = (await rest(`profiles?select=full_name,education_stage_key&id=eq.${identity.id}&limit=1`))?.[0] || {};
    const stages = Array.isArray(product.audience_stage_keys) ? product.audience_stage_keys : [];
    if (stages.length && (!profile.education_stage_key || !stages.includes(profile.education_stage_key))) {
      return json({ code: 'AUDIENCE_MISMATCH', error: 'This product is not available for your education stage.' }, 403);
    }
    if (product.product_type === 'one_time') {
      const entitlements = await rest(`mela_user_learning_entitlements?select=id&user_id=eq.${identity.id}&product_key=eq.${encodeURIComponent(productKey)}&status=eq.active&limit=1`);
      if (entitlements?.length) return json({ code: 'ALREADY_ENTITLED', error: 'You already have this learning pack.' }, 409);
    }

    const mode = paymentMode();
    const recent = await rest(`mela_learning_payment_attempts?select=tx_ref,status,checkout_url,mode,expected_amount_minor,expected_currency&user_id=eq.${identity.id}&product_key=eq.${encodeURIComponent(productKey)}&mode=eq.${mode}&status=in.(initiated,pending)&limit=1`);
    const reusable = (recent || []).find((row: any) => row.status === 'pending' && safeCheckout(row.checkout_url) && row.mode === mode && Number(row.expected_amount_minor) === amountMinor && row.expected_currency === currency);
    if (reusable) {
      return json({ checkout_url: reusable.checkout_url, tx_ref: reusable.tx_ref, mode, reused: true, product: { product_key: productKey, name: product.product_name, amount: (amountMinor / 100).toFixed(2), currency } });
    }
    if (recent?.length) return json({ code: 'CHECKOUT_PENDING', tx_ref: recent[0].tx_ref, error: 'A checkout is already being processed. Verify it before starting another.' }, 409);

    const key = chapaKey();
    const fullName = String(profile.full_name || 'Mela Learner').trim();
    const parts = fullName.split(/\s+/).filter(Boolean);
    const firstName = parts[0] || 'Mela';
    const lastName = parts.slice(1).join(' ') || 'Learner';
    const txRef = `mela_learning_${mode}_${Date.now()}_${crypto.randomUUID().replaceAll('-', '').slice(0, 12)}`;
    const amount = (amountMinor / 100).toFixed(2);
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const callbackUrl = `${supabaseUrl}/functions/v1/mela-learning-payment-callback`;
    const returnBase = String(Deno.env.get('MELA_RETURN_URL') || '').replace(/\/$/, '');
    const returnUrl = returnBase ? `${returnBase}?learning_payment=return&tx_ref=${encodeURIComponent(txRef)}` : undefined;

    const inserted = await rest('mela_learning_payment_attempts?select=id', {
      method: 'POST', headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ user_id: identity.id, product_key: productKey, mode, tx_ref: txRef, expected_amount_minor: amountMinor, expected_currency: currency, status: 'initiated' }),
    });
    const paymentId = inserted?.[0]?.id;
    if (!paymentId) throw Object.assign(new Error('Payment attempt could not be created'), { status: 500 });

    const payload: any = {
      amount, currency, email: identity.email, first_name: firstName, last_name: lastName, tx_ref: txRef, callback_url: callbackUrl,
      customization: { title: `Mela — ${product.product_name}`, description: 'Mela learning access' },
      meta: { product_key: productKey, payment_mode: mode },
    };
    if (returnUrl) payload.return_url = returnUrl;

    const providerResponse = await fetch('https://api.chapa.co/v1/transaction/initialize', {
      method: 'POST', headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' }, body: JSON.stringify(payload), signal: AbortSignal.timeout(15000),
    });
    const text = await providerResponse.text();
    let provider: any = {};
    try { provider = text ? JSON.parse(text) : {}; } catch {}
    const checkoutUrl = provider?.data?.checkout_url;
    if (!providerResponse.ok || provider?.status !== 'success' || !safeCheckout(checkoutUrl)) {
      await patchUnfinished(paymentId, { failure_reason: provider?.message || `Chapa initialize ${providerResponse.status}`, updated_at: new Date().toISOString() });
      return json({ code: 'CHAPA_INITIALIZE_FAILED', error: provider?.message || 'Unable to initialize Chapa checkout.' }, 502);
    }

    const updated = await patchUnfinished(paymentId, { status: 'pending', checkout_url: checkoutUrl, provider_status: provider?.status || 'success', updated_at: new Date().toISOString() });
    if (!updated?.length) {
      const latest = (await rest(`mela_learning_payment_attempts?id=eq.${encodeURIComponent(paymentId)}&select=status,checkout_url&limit=1`))?.[0];
      if (latest?.status !== 'pending' || !latest?.checkout_url) throw Object.assign(new Error('Payment state changed before checkout became available.'), { status: 409 });
    }
    return json({ checkout_url: checkoutUrl, tx_ref: txRef, mode, product: { product_key: productKey, name: product.product_name, amount, currency } });
  } catch (e: any) {
    console.error('mela-learning-checkout', e);
    return json({ code: e?.code, error: e instanceof Error ? e.message : 'Unexpected error' }, e?.status || 500);
  }
});
