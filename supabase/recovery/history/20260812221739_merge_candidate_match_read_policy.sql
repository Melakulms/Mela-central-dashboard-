-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812221739
drop policy if exists "Candidates read own opportunity matches" on public.candidate_matches;
drop policy if exists "Employer teams read candidate matches" on public.candidate_matches;
drop policy if exists "Candidate matches readable by authorized users" on public.candidate_matches;
create policy "Candidate matches readable by authorized users" on public.candidate_matches for select to authenticated
using (
  (
    candidate_id=(select auth.uid())
    and (opportunity_id is null or exists(select 1 from public.opportunities o where o.id=opportunity_id and o.status='open' and o.verified_active=true and o.deadline>=current_date))
  )
  or exists(select 1 from public.employers e where e.id=employer_id and e.owner_id=(select auth.uid()))
  or exists(select 1 from public.employer_members m where m.employer_id=candidate_matches.employer_id and m.user_id=(select auth.uid()) and m.status='active')
  or private.is_admin_user()
);
;
