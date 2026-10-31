import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// MELA staging Telegram backend. No payment acceptance, approval, or account linking.
// Secrets must be supplied in Supabase Edge Functions > Secrets, never in code.
const STAGING_URL = "https://tungqfmypuwzeyrtaseh.supabase.co";
const BOT_USERNAME = "mela_edu_bot";
const FUNCTION_SLUG = "mela-telegram-bot";
const encoder = new TextEncoder();

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

function secureEqual(provided: string, expected: string): boolean {
  const a = encoder.encode(provided);
  const b = encoder.encode(expected);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i++) difference |= a[i] ^ b[i];
  return difference === 0;
}

function credentials() {
  const token = Deno.env.get("MELA_TELEGRAM_BOT_TOKEN") || "";
  const secret = Deno.env.get("MELA_TELEGRAM_WEBHOOK_SECRET") || "";
  const projectUrl = Deno.env.get("SUPABASE_URL") || "";
  return {
    token,
    secret,
    safeProject: projectUrl === STAGING_URL,
    configured: /^[0-9]{5,}:[A-Za-z0-9_-]{20,}$/.test(token)
      && /^[A-Za-z0-9_-]{32,256}$/.test(secret)
      && projectUrl === STAGING_URL,
  };
}

async function telegramCall(token: string, method: string, payload: Record<string, unknown>) {
  const response = await fetch("https://api.telegram.org/bot" + token + "/" + method, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error("Telegram API HTTP " + response.status);
  const data = await response.json();
  if (!data || data.ok !== true) throw new Error("Telegram API returned an error");
  return data.result;
}


const TEST_TABLE_URL = STAGING_URL + "/rest/v1/mela_telegram_staging_test_cases";

async function testChatHash(chatId: number, token: string): Promise<string> {
  const signingKey = await crypto.subtle.importKey(
    "raw", encoder.encode(token), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", signingKey, encoder.encode(String(chatId)));
  return Array.from(new Uint8Array(signature), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sandboxApi(
  key: string,
  method: "GET" | "POST",
  url: string,
  body?: Record<string, string>
): Promise<Response> {
  return fetch(url, {
    method,
    headers: {
      apikey: key,
      authorization: "Bearer " + key,
      ...(body ? { "content-type": "application/json", prefer: "return=minimal" } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(10000),
  });
}

async function sandboxCommand(
  cfg: ReturnType<typeof credentials>,
  chatId: number,
  messageText: string
): Promise<string> {
  const parts = messageText.trim().split(/\s+/);
  const command = parts[0].toLowerCase().split("@")[0];
  if (command === "/testapprove") {
    return "BLOCKED: A Telegram message cannot approve a payment or grant paid access. This is a staging-only safety test.";
  }
  if (parts.length > 2) return "Only one TEST- reference is accepted. Never send a real transaction number.";
  const raw = parts[1] || "";
  const ref = command === "/testpay" && !raw
    ? "TEST-" + crypto.randomUUID().replace(/-/g, "").slice(0, 12).toUpperCase()
    : raw.toUpperCase();
  if (!/^TEST-[A-Z0-9]{6,18}$/.test(ref)) {
    return "Use a FICTIONAL reference like TEST-MELA001. Real transaction references are not accepted.";
  }
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!key || !cfg.configured) {
    return "Staging test storage is unavailable. No payment has been submitted.";
  }
  const hash = await testChatHash(chatId, cfg.token);
  const params = new URLSearchParams({
    select: "status,created_at",
    chat_hash: "eq." + hash,
    test_reference: "eq." + ref,
    limit: "1",
  });
  const existingResponse = await sandboxApi(key, "GET", TEST_TABLE_URL + "?" + params.toString());
  if (!existingResponse.ok) throw new Error("test case lookup unavailable");
  const rows = await existingResponse.json();
  if (Array.isArray(rows) && rows.length) {
    return "SIMULATION ONLY: " + ref + " has status " + String(rows[0].status) +
      ". No money has been received and no account has been upgraded." +
      (command === "/testpay" ? "\nDuplicate submission safely blocked." : "");
  }
  if (command === "/teststatus") {
    return "No simulated case found for " + ref + " in this private Telegram chat.";
  }
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const recentParams = new URLSearchParams({
    select: "id", chat_hash: "eq." + hash, created_at: "gte." + since, limit: "5",
  });
  const recentResponse = await sandboxApi(key, "GET", TEST_TABLE_URL + "?" + recentParams.toString());
  if (!recentResponse.ok) throw new Error("test rate limit lookup unavailable");
  const recent = await recentResponse.json();
  if (!Array.isArray(recent)) throw new Error("unexpected test rate-limit result");
  if (recent.length >= 5) return "Daily test limit reached (5). Try again tomorrow. No payment was taken.";
  const created = await sandboxApi(key, "POST", TEST_TABLE_URL, { chat_hash: hash, test_reference: ref });
  if (created.status === 409) return "Duplicate simulated reference detected. Check it with /teststatus " + ref;
  if (created.status !== 201) throw new Error("test case insert unavailable");
  return "STAGING TEST ONLY: simulated reference " + ref +
    " recorded as pending_test.\nNo real money, bank verification, approval, or access was granted." +
    "\nSend /teststatus " + ref + " to check the stored status.";
}


async function billingCommand(cfg: ReturnType<typeof credentials>, chatId: number, messageText: string): Promise<string> {
  const [rawCommand,arg,...rest] = messageText.trim().split(/\s+/);
  const command = rawCommand.toLowerCase().split("@")[0];
  const action = command === "/plans" ? "plans" : command === "/link" ? "link" : command === "/unlink" ? "unlink" : "status";
  if (rest.length) return "Only one one-time link code may be submitted.";
  if (command === "/link" && !/^[A-F0-9]{32}$/.test(arg || "")) {
    return "Create a one-time Telegram link code from My Account in the MELA app, then send /link CODE. It expires in five minutes.";
  }
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (!cfg.configured || !key) return "Private billing status is unavailable; no payment was accepted.";
  const response = await fetch(STAGING_URL + "/rest/v1/rpc/mela_billing_bot_v1", {
    method:"POST",
    headers:{apikey:key,authorization:"Bearer "+key,"content-type":"application/json"},
    body:JSON.stringify({p_action:action,p_data:{chat_id:String(chatId),...(arg?{code:arg}:{})}}),
    signal:AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error("MELA billing service HTTP " + response.status);
  const data = await response.json();
  if (action === "plans") {
    const lines = (Array.isArray(data.plans)?data.plans:[]).map((p: any) =>
      String(p.name) + ": " + String(p.amount_etb) + " ETB / 30 days. New paid member referral reward " + String(p.commission_etb) + " ETB.");
    return "MELA Plans\nFree Core: free.\n" + lines.join("\n") +
      (data.open ? "\nCreate a payment order in your signed-in MELA account." :
       "\nPayments are not open yet. DO NOT transfer money.");
  }
  if (action === "link") return data.linked === true
    ? "Your private Telegram chat is linked to your MELA account. Use /subscription to see status. Linking never approves payments."
    : "Link failed. Code expired, invalid, or chat already linked. Generate a new code from My Account.";
  if (action === "unlink") return "This private chat has been unlinked from MELA.";
  if (data.linked !== true) return "Private chat not linked. Open My Account in MELA, create a one-time code and send /link CODE.";
  const list=Array.isArray(data.orders)?data.orders:[];
  if (!list.length) return "Account linked. No payment orders have been submitted.";
  return "Latest MELA orders:\n" + list.map((p:any)=> (p.plan_key==="pro_monthly"?"Pro":"Premium") +
    " - " + String(p.amount_minor/100) + " ETB - " + String(p.status)).join("\n") +
    "\nOnly independent bank verification can activate a subscription.";
}

function replyFor(text: string): string {
  const command = text.trim().split(/\s+/)[0].toLowerCase().split("@")[0];
  switch (command) {
    case "/start":
      return "Welcome to MELA Education! 🇪🇹\n\nFree education continues in the MELA app. Public payment collection is closed. The owner-only 1 birr test is available through /pay.\n\nUse /help to see what I can do. Please do not share banking PINs, passwords, or payment screenshots here.";
    case "/help":
      return "MELA Education Bot (staging)\n\n/plans — Pro/Premium pricing\n/link CODE — Link MELA account\n/unlink — Disconnect\n/subscription — Linked order status\n/start — Welcome\n/help — Commands\n/pay — Payment availability\n/verify — Payment verification guidance\n/status — Account and payment status guidance\n/privacy — Privacy notice\n/testpay TEST-MELA001 — Record a simulated test\n/teststatus TEST-MELA001 — Check simulated status\n/testapprove TEST-MELA001 — Confirm approval is blocked\n\nPublic payment collection and automated approval are disabled. /pay opens the protected owner test page. /testpay remains a simulation with no real money.";
    case "/pay":
      return "Public payment collection is closed. Melaku's private 1 birr transfer test is available on the protected page below. Only the MELA owner account can use it. Create a test there BEFORE transferring money. Do not send banking details or receipts to this chat.\n\nhttps://mela-private-payment-test.cloudyjelly10.chatgpt.site";
    case "/verify":
      return "For your private owner test, submit and review your transfer on the protected page below. Sign in with MELA and your authenticator. Check the actual incoming record in your bank or Telebirr app before confirming it. This is manual verification, not an automatic bank lookup.\n\nhttps://mela-private-payment-test.cloudyjelly10.chatgpt.site";
    case "/status":
      return "Check your private transfer test status on the protected page below. This Telegram chat is not linked to your MELA account; no private records are shown here.\n\nhttps://mela-private-payment-test.cloudyjelly10.chatgpt.site";
    case "/privacy":
      return "This bot responds to commands in private chats. It does not collect payment details, identity documents, or MELA passwords in Telegram. The separate owner-only test page stores test references and manual verification records after MELA sign-in. Do not send sensitive information here. Private account linking and consent must be completed before enabling personalized services.";
    default:
      return "MELA staging bot is in test mode. Type /help to see available commands. Please do not send payment screenshots or account credentials.";
  }
}

export async function handler(req: Request): Promise<Response> {
  const path = new URL(req.url).pathname;
  const cfg = credentials();
  if (!cfg.safeProject) return json({ ok: false, error: "staging_project_mismatch" }, 503);

  if (req.method === "GET" && (path.endsWith("/" + FUNCTION_SLUG) || path.endsWith("/" + FUNCTION_SLUG + "/health"))) {
    // Read-only health. Never set or reclaim the Telegram webhook during a GET.
    // This prevents staging health checks from undoing a deliberate production cutover.
    let webhookStatus = "not_configured";
    if (cfg.configured) {
      try {
        const me = await telegramCall(cfg.token, "getMe", {});
        if (String(me?.username || "").toLowerCase() !== BOT_USERNAME) {
          webhookStatus = "bot_username_mismatch";
        } else {
          const current = await telegramCall(cfg.token, "getWebhookInfo", {});
          const target = STAGING_URL + "/functions/v1/" + FUNCTION_SLUG;
          webhookStatus = current?.url === target ? "registered_here" :
            current?.url ? "registered_elsewhere" : "not_registered";
        }
      } catch (e) {
        console.error("MELA Telegram read-only health failed:", e instanceof Error ? e.message : "unknown");
        webhookStatus = "telegram_api_error";
      }
    }
    let sandboxStorage = "unavailable";
    const sandboxKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
    if (sandboxKey) {
      try {
        const check = await sandboxApi(sandboxKey, "GET", TEST_TABLE_URL + "?select=id&limit=1");
        sandboxStorage = check.ok ? "ready" : "unavailable";
      } catch {
        sandboxStorage = "unavailable";
      }
    }
    return json({
      ok: true, service: "MELA Telegram staging backend", bot: "@" + BOT_USERNAME,
      configured: cfg.configured, webhook_status: webhookStatus, sandbox_storage: sandboxStorage,
      payments_enabled: false,
      supported_commands: ["/start", "/help", "/plans", "/link", "/unlink", "/subscription", "/pay", "/verify", "/status", "/privacy"],
    });
  }

  if (req.method === "POST" && (path.endsWith("/" + FUNCTION_SLUG + "/setup") ||
      (path.endsWith("/" + FUNCTION_SLUG) && req.headers.has("x-mela-telegram-setup-secret")))) {
    // Disabled after production endpoint was prepared; staging cannot reclaim webhook.
    return json({ ok: false, error: "staging_setup_disabled" }, 403);
  }

  if (req.method === "POST" && path.endsWith("/" + FUNCTION_SLUG)) {
    if (!cfg.configured) return json({ ok: false, error: "bot_secrets_not_configured" }, 503);
    const providedSecret = req.headers.get("x-telegram-bot-api-secret-token") || "";
    if (!secureEqual(providedSecret, cfg.secret)) return json({ ok: false, error: "unauthorized" }, 401);
    if ((req.headers.get("content-length") || "").match(/^\d+$/)
        && Number(req.headers.get("content-length")) > 16384) {
      return json({ ok: false, error: "payload_too_large" }, 413);
    }
    let update: any;
    try {
      const raw = await req.text();
      if (raw.length > 16384) return json({ ok: false, error: "payload_too_large" }, 413);
      update = JSON.parse(raw);
    } catch {
      return json({ ok: false, error: "invalid_json" }, 400);
    }
    const message = update?.message;
    const chat = message?.chat;
    // Never process group chats, media attachments, callbacks, or someone else's identity.
    if (!Number.isSafeInteger(update?.update_id)
        || chat?.type !== "private"
        || !Number.isSafeInteger(chat?.id)
        || message?.from?.id !== chat.id
        || message?.from?.is_bot) {
      return json({ ok: true, ignored: true });
    }

    const messageText = typeof message.text === "string" && message.text.length <= 4096 ? message.text : null;
    let answer: string;
    if (messageText && /^\/(plans|link|unlink|subscription)(?:@mela_edu_bot)?(?:\s|$)/i.test(messageText.trim())) {
      try {
        answer = await billingCommand(cfg, chat.id, messageText);
      } catch (e) {
        console.error("MELA staging billing command failed:",e instanceof Error?e.message:"unknown");
        answer = "MELA subscription status is temporarily unavailable. No payment or approval happened.";
      }
    } else if (messageText && /^\/test(pay|status|approve)(?:@mela_edu_bot)?(?:\s|$)/i.test(messageText.trim())) {
      try {
        answer = await sandboxCommand(cfg, chat.id, messageText);
      } catch (e) {
        console.error("MELA staging sandbox test failed:", e instanceof Error ? e.message : "unknown");
        answer = "The staging test service is unavailable. No payment was submitted or approved.";
      }
    } else {
      answer = messageText
        ? replyFor(messageText)
        : "MELA cannot process attachments or sensitive documents through this test bot. Send /help for commands.";
    }
    try {
      await telegramCall(cfg.token, "sendMessage", { chat_id: chat.id, text: answer, protect_content: true });
      return json({ ok: true });
    } catch (e) {
      console.error("MELA Telegram response failed:", e instanceof Error ? e.message : "unknown");
      return json({ ok: false, error: "telegram_delivery_failed" }, 502);
    }
  }

  return json({ ok: false, error: "not_found" }, 404);
}

Deno.serve(handler);
