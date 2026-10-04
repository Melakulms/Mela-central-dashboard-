-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814132523
create table if not exists public.assessment_language_certifications (
  assessment_id uuid not null references public.skill_assessments(id) on delete cascade,
  language_code text not null references public.platform_languages(language_code) on update cascade on delete restrict,
  status text not null default 'draft' check (status in ('draft','in_review','certified','rejected')),
  reviewer_notes text,
  reviewed_by uuid references public.profiles(id) on delete set null,
  certified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(assessment_id,language_code)
);
create index if not exists assessment_language_certifications_language_status_idx on public.assessment_language_certifications(language_code,status,assessment_id);
create index if not exists assessment_language_certifications_reviewed_by_idx on public.assessment_language_certifications(reviewed_by) where reviewed_by is not null;
alter table public.assessment_language_certifications enable row level security;
revoke all on public.assessment_language_certifications from public,anon,authenticated;
grant select on public.assessment_language_certifications to authenticated,service_role;
grant insert,update on public.assessment_language_certifications to authenticated,service_role;
grant delete on public.assessment_language_certifications to service_role;
drop policy if exists assessment_language_certifications_read on public.assessment_language_certifications;
create policy assessment_language_certifications_read on public.assessment_language_certifications for select to authenticated using (true);
drop policy if exists assessment_language_certifications_admin_insert on public.assessment_language_certifications;
create policy assessment_language_certifications_admin_insert on public.assessment_language_certifications for insert to authenticated with check (private.is_admin_user());
drop policy if exists assessment_language_certifications_admin_update on public.assessment_language_certifications;
create policy assessment_language_certifications_admin_update on public.assessment_language_certifications for update to authenticated using (private.is_admin_user()) with check (private.is_admin_user());

insert into public.assessment_language_certifications(assessment_id,language_code,status,reviewer_notes,certified_at)
select a.id,'en','certified','English source assessment',now()
from public.skill_assessments a
on conflict(assessment_id,language_code) do update set status='certified',reviewer_notes='English source assessment',certified_at=coalesce(public.assessment_language_certifications.certified_at,now()),updated_at=now();

insert into public.assessment_language_certifications(assessment_id,language_code,status,reviewer_notes)
select a.id,l.language_code,'draft','Requires qualified bilingual review of the exact translated prompts, choices, instructions and scoring equivalence before credential use.'
from public.skill_assessments a
cross join public.platform_languages l
where l.language_code in ('am','om','ti','so')
on conflict(assessment_id,language_code) do nothing;

create or replace function public.assessment_language_is_certified(p_assessment_id uuid,p_language text default null)
returns boolean
language sql
stable
security invoker
set search_path to ''
as $function$
  select exists(
    select 1
    from public.assessment_language_certifications c
    where c.assessment_id=p_assessment_id
      and c.language_code=(case coalesce(p_language,(select preferred_language from public.profiles where id=(select auth.uid())))
        when 'English' then 'en' when 'Amharic' then 'am' when 'Afaan Oromo' then 'om' when 'Tigrinya' then 'ti' when 'Somali' then 'so'
        when 'en' then 'en' when 'am' then 'am' when 'om' then 'om' when 'ti' then 'ti' when 'so' then 'so' else 'en' end)
      and c.status='certified'
  );
$function$;
grant execute on function public.assessment_language_is_certified(uuid,text) to authenticated,service_role;

create or replace function private.enforce_proctoring_consent()
returns trigger
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_proctored boolean;
  v_language text;
begin
  select is_proctored into v_proctored from public.skill_assessments where id=new.assessment_id;
  if coalesce(v_proctored,false) then
    if not public.has_current_policy_acknowledgement('proctoring') then
      raise exception 'proctoring consent is required before starting this assessment';
    end if;
    select preferred_language into v_language from public.profiles where id=(select auth.uid());
    if not public.assessment_language_is_certified(new.assessment_id,v_language) then
      raise exception 'this verified assessment language version is not yet human-certified for credential use';
    end if;
  end if;
  return new;
end;
$function$;
;
