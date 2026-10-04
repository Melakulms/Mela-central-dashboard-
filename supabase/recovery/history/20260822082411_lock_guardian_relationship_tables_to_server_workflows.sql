-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822082411
revoke insert, update, delete on table public.guardian_relationships from authenticated; revoke insert, update, delete on table public.parent_link_invites from authenticated; alter function public.request_my_guardian_consent(text,text,text) security definer set search_path = '';
;
