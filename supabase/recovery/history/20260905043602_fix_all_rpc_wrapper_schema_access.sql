-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260905043602

-- Systemic bug: every one of these public wrapper functions is a thin pass-through
-- to a private.* implementation (e.g. `select private.foo(...)`), but the wrapper
-- itself is NOT security definer. `authenticated`/`anon` have no USAGE on schema
-- `private`, so every one of these calls fails at runtime with
-- "permission denied for schema private" -- for every real user, on essentially
-- every core action (dashboard load, practice sessions, arena, video calls,
-- challenges, classrooms, question sessions, etc).
--
-- The real authorization logic lives inside each private.* function via auth.uid()
-- checks -- confirmed on complete_mentorship_session, which correctly rejected a
-- non-mentor caller with a business-logic error after being fixed the same way.
-- Making the wrapper SECURITY DEFINER does not bypass any check; it lets the call
-- reach the checks that are already there. All 95 wrappers are owned by `postgres`,
-- which already has USAGE on `private` -- same safe pattern as the mentorship fix.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_roles ro ON ro.oid = p.proowner
    WHERE n.nspname = 'public'
      AND pg_get_functiondef(p.oid) ILIKE '%private.%'
      AND p.prosecdef = false
      AND ro.rolname = 'postgres'
      AND has_function_privilege('authenticated', p.oid, 'execute')
  LOOP
    EXECUTE format('ALTER FUNCTION %s SECURITY DEFINER', r.sig);
  END LOOP;
END $$;

;
