-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812224510
alter table public.profiles add column if not exists contact_phone text;
revoke update (phone_number, auth_primary_method, auth_provider, email_verified, phone_verified) on public.profiles from authenticated;
grant update (contact_phone) on public.profiles to authenticated;
grant select (contact_phone) on public.profiles to authenticated;

;
