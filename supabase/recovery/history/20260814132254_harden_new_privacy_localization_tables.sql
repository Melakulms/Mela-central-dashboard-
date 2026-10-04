-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814132254
create index if not exists data_subject_requests_handled_by_idx on public.data_subject_requests(handled_by) where handled_by is not null;
create index if not exists platform_translation_glossary_language_code_idx on public.platform_translation_glossary(language_code);
create index if not exists user_policy_ack_policy_version_idx on public.user_policy_acknowledgements(policy_key,policy_version);

drop policy if exists platform_translation_cache_client_deny on public.platform_translation_cache;
create policy platform_translation_cache_client_deny on public.platform_translation_cache as restrictive for all to anon,authenticated using (false) with check (false);

drop policy if exists dsr_owner_cancel on public.data_subject_requests;
drop policy if exists dsr_admin_update on public.data_subject_requests;
drop policy if exists dsr_owner_or_admin_update on public.data_subject_requests;
create policy dsr_owner_or_admin_update on public.data_subject_requests
for update to authenticated
using (
  private.is_admin_user()
  or (user_id=(select auth.uid()) and status='pending')
)
with check (
  private.is_admin_user()
  or (user_id=(select auth.uid()) and status='cancelled')
);
;
