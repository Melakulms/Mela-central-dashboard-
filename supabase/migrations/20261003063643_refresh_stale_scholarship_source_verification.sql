update public.opportunities
set source_verified_at=now(),
    source_last_checked_at=now(),
    source_notes='Official Chevening application timeline re-verified on 2026-10-03. Applications for the 2027-28 cycle close 6 October 2026 at 11:00 UTC.',
    moderation_notes='Official Chevening source re-verified for launch catalog on 2026-10-03.',
    reviewed_at=now(),
    verified_active=true,
    updated_at=now()
where source_url='https://www.chevening.org/scholarships/application-timeline/'
  and title='Chevening Scholarships — 2027–28';

update public.opportunities
set source_verified_at=now(),
    source_last_checked_at=now(),
    source_notes='Official Knight-Hennessy admission page re-verified on 2026-10-03. Applications for the 2027 cohort close 6 October 2026 at 1:00 PM Pacific Time.',
    moderation_notes='Official Stanford Knight-Hennessy source re-verified for launch catalog on 2026-10-03.',
    reviewed_at=now(),
    verified_active=true,
    updated_at=now()
where source_url='https://knight-hennessy.stanford.edu/admission'
  and title='Knight-Hennessy Scholars — Stanford 2027 Cohort';

update public.opportunities
set deadline='2026-11-30',
    source_verified_at=now(),
    source_last_checked_at=now(),
    source_notes='Official ALU financial-aid and January 2027 admissions pages re-verified on 2026-10-03. Mastercard Foundation scholarships remain available for eligible applicants, with January 2027 applications closing 30 November 2026.',
    moderation_notes='Official African Leadership University source re-verified and January 2027 deadline corrected to 30 November 2026.',
    reviewed_at=now(),
    verified_active=true,
    updated_at=now()
where source_url='https://www.alueducation.com/financial-aid-at-alu/'
  and title='Mastercard Foundation Scholars Program at African Leadership University — January 2027 Intake';
