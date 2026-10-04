-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812215341
drop policy if exists "Students create mentorship requests" on public.mentorship_requests;
drop policy if exists "Mentorship requests readable by participants" on public.mentorship_requests;
drop policy if exists "Mentees create mentorship requests" on public.mentorship_requests;
drop policy if exists "Mentors respond to requests" on public.mentorship_requests;
drop policy if exists "Mentees cancel pending requests" on public.mentorship_requests;
drop policy if exists "Admins update mentorship requests" on public.mentorship_requests;

create policy "Mentorship requests readable by participants" on public.mentorship_requests for select to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
create policy "Mentees create mentorship requests" on public.mentorship_requests for insert to authenticated
with check (
  mentee_id=(select auth.uid()) and mentor_id<>(select auth.uid()) and status='pending' and responded_at is null
  and (preferred_at is null or preferred_at>now())
  and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role)
  and exists(select 1 from public.mentor_profiles mp where mp.user_id=mentor_id and mp.verified=true and mp.active=true)
);
create policy "Mentors respond to requests" on public.mentorship_requests for update to authenticated
using (mentor_id=(select auth.uid()) and status='pending')
with check (mentor_id=(select auth.uid()) and status in ('accepted','declined'));
create policy "Mentees cancel pending requests" on public.mentorship_requests for update to authenticated
using (mentee_id=(select auth.uid()) and status='pending')
with check (mentee_id=(select auth.uid()) and status='cancelled');
create policy "Admins update mentorship requests" on public.mentorship_requests for update to authenticated
using (private.is_admin_user()) with check (private.is_admin_user());

-- Restore session policies too, in case an older schema version replaced them.
drop policy if exists "mentorship: participants manage" on public.mentorship_sessions;
drop policy if exists "Mentorship sessions readable by participants" on public.mentorship_sessions;
drop policy if exists "Mentorship sessions update by participants" on public.mentorship_sessions;
drop policy if exists "Admins delete mentorship sessions" on public.mentorship_sessions;
create policy "Mentorship sessions readable by participants" on public.mentorship_sessions for select to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
create policy "Mentorship sessions update by participants" on public.mentorship_sessions for update to authenticated
using (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user())
with check (mentor_id=(select auth.uid()) or mentee_id=(select auth.uid()) or private.is_admin_user());
create policy "Admins delete mentorship sessions" on public.mentorship_sessions for delete to authenticated using (private.is_admin_user());

;
