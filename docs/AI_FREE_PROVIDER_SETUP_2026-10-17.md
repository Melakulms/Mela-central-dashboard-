# MELA AI without a payment card (Groq Free tier)

Date: 2026-10-17. This is a **limited, optional free provider** for learner career coaching and administrator AI worker advice; it does not certify unattended automation.

## Phone-only setup

1. Open https://console.groq.com/keys and create a **Groq Free** account/key. Do not upgrade to the paid Developer plan.
2. In Supabase production project `duizgtmbptmlbyipreqg`, navigate to **Edge Functions → Secrets**, and save:
   - Secret name: `GROQ_API_KEY`
   - Secret value: your newly generated private Groq API key.
3. Keep `MELA_AI_PROVIDER` unset (Groq is selected automatically if this key exists). Existing paid OpenAI keys remain supported only when Groq is absent or `MELA_AI_PROVIDER=openai` is explicitly configured.
4. Sign in as a verified administrator with MFA. Open **AI Workforce → AI service readiness**, press **Refresh AI workforce**; the status should show **Configured (Groq free API)**.
5. Sign in to the learner app with a student account and ask the AI Career Coach a non-sensitive career question. Then test an individually selected AI worker using a harmless educational query. Inspect completed runs. Configuration alone is not evidence of a functioning AI response.
6. Never paste a key in chat, GitHub, the mobile app, screenshots, or the client-side `VITE_*` environment settings.

## Operational boundaries

- Groq Free-tier usage is limited and can return HTTP 429. MELA also keeps its independent daily limit (production currently 10 attempts/user and 100 globally). Free access is **not** a capacity guarantee for a public launch.
- Gateway auth and per-user quotas, 800-token max completion, age-appropriate educational system instructions, and restrictions against arbitrary client model changes remain enforced.
- The gateway uses only the Groq hosted `llama-3.3-70b-versatile` model and `https://api.groq.com/openai/v1/chat/completions` when Groq is configured. It does not call the paid OpenAI endpoint in that mode.
- No automatic sends, publishing, admin changes, payouts, or privileged data access are allowed from AI-generated text. Worker responses are advisory.
- Do not submit passwords, ID scans, contact information, or sensitive child data in AI prompts; review the Groq Free plan and Data Controls before involving real students. Groq may retain certain requests for reliability/abuse monitoring depending on settings.
- The dashboard reports only whether server configuration and registered workers exist; a genuine authenticated model answer and independently reviewed access controls remain launch gates.

References: https://console.groq.com/docs/billing-faqs, https://console.groq.com/docs/quickstart, https://console.groq.com/docs/your-data, https://console.groq.com/docs/rate-limits.
