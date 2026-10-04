-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822090422
drop policy if exists "Languages readable by owner or employer" on public.profile_languages; create policy "Languages readable by owner or public employer" on public.profile_languages for select to authenticated using ((user_id = (select auth.uid())) or (verified = true and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.role in ('employer'::user_role,'admin'::user_role))));
;
