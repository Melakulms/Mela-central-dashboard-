-- Match teachers to BOTH their independently approved teaching subject and grade.
-- The existing function checked subject authorization but did not restrict grade.
-- Keep all MFA admin rights unchanged and preserve both trusted teacher grants.
create or replace function private.question_reviewer_allowed_v18(p_uid uuid, p_program_key text)
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select (
    p_uid = (select auth.uid()) and private.is_admin_user()
  ) or (
    p_uid = (select auth.uid()) and exists(
      select 1
      from public.teacher_profiles t
      join public.mela_learning_programs lp on lp.program_key = p_program_key
      where t.user_id = p_uid
        and t.verification_status = 'approved'
        -- Only exact subject names/keys, ignoring case and surrounding spaces.
        and exists(
          select 1 from unnest(coalesce(t.subjects_taught, '{}'::text[])) s(subject)
          where lower(btrim(s.subject)) = lower(btrim(lp.subject_key))
             or lower(btrim(s.subject)) = lower(btrim(lp.subject_title))
        )
        -- School teachers: verified grade number; university/TVET: verified stage.
        and exists(
          select 1 from unnest(coalesce(t.grade_levels, '{}'::text[])) g(level)
          where lower(btrim(g.level)) = coalesce(lp.grade_level::text, lower(btrim(lp.stage_key)))
        )
        -- Independent authorization remains mandatory; submitting a profile
        -- or editing any education fields does not grant reviewer access.
        and (
          exists(
            select 1 from private.educator_review_authorizations a
            where a.user_id = p_uid and a.active
              and exists(
                select 1 from unnest(coalesce(a.subject_areas, '{}'::text[])) allowed(subject)
                where lower(btrim(allowed.subject)) = lower(btrim(lp.subject_key))
                   or lower(btrim(allowed.subject)) = lower(btrim(lp.subject_title))
              )
          )
          or exists(
            select 1 from public.educator_profiles e
            where e.user_id = p_uid and e.verified and e.active
              and exists(
                select 1 from unnest(coalesce(e.subject_areas, '{}'::text[])) allowed(subject)
                where lower(btrim(allowed.subject)) = lower(btrim(lp.subject_key))
                   or lower(btrim(allowed.subject)) = lower(btrim(lp.subject_title))
              )
          )
        )
    )
  );
$function$;
