# Recovered deployed Edge Function source

These versioned files preserve the exact deployed source retrieved on 4 October 2026 before corresponding repairs. They are evidence and recovery material, not current deployment entrypoints. Some contain known authorization, mode, amount, race or retry defects. Do not redeploy them as routine rollback.

Maintained repaired functions are under `supabase/functions/<name>/index.ts`. The recovered `chapa-initialize` v4 and `mela-learning-checkout` v2 are superseded by maintained implementations under `supabase/functions`. Checkout concurrency and reconciliation limitations are tracked in the 5 October audit report. This archive is separate from the frozen 607-file SQL migration archive and is not a complete platform backup.

Environment variable lookups are preserved; no merchant secret or real payment data was read or inserted into these files.
