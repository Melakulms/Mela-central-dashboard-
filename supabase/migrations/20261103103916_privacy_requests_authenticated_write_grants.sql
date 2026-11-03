-- Staging migration 20261103103916. Staging lacked authenticated INSERT/UPDATE
-- grants even though RLS policies existed. Production already has these grants.
-- The preceding BEFORE UPDATE trigger restricts transitions; RLS limits owners.
grant insert, update on table public.data_subject_requests to authenticated;
