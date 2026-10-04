-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002054515
-- Public visibility must use current employer verification, not only the cached vacancy flag.
alter policy "Opportunities readable" on public.opportunities using (
 (status='open' and verified_active=true and moderation_status='approved' and deadline>=current_date
  and (employer_id is null or exists(select 1 from public.employers e where e.id=opportunities.employer_id and e.verified=true and e.verification_status='verified')))
 or exists(select 1 from public.employers e where e.id=opportunities.employer_id and e.owner_id=(select auth.uid()))
 or exists(select 1 from public.employer_members m where m.employer_id=opportunities.employer_id and m.user_id=(select auth.uid()) and m.status='active')
 or private.is_admin_user()
);
alter policy "Students submit applications" on public.applications with check (
 applicant_id=(select auth.uid()) and user_id=applicant_id and status='submitted'
 and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.role='student'::public.user_role and p.account_status='active' and p.deleted_at is null and (p.email_verified or p.phone_verified))
 and exists(select 1 from public.opportunities o where o.id=applications.opportunity_id and o.status='open' and o.moderation_status='approved' and o.verified_active=true and o.deadline>=current_date and o.application_method in ('mela','both')
   and (o.employer_id is null or exists(select 1 from public.employers e where e.id=o.employer_id and e.verified=true and e.verification_status='verified')))
);

;
