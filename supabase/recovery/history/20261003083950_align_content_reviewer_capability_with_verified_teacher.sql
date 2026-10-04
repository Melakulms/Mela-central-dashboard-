-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261003083950
create or replace function private.can_review_questions_v18()
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare v_uid uuid := (select auth.uid());
begin
  if v_uid is null then return false; end if;
  if private.is_admin_user() then return true; end if;
  return exists(
    select 1
    from public.educator_profiles e
    join public.teacher_profiles t on t.user_id=e.user_id and t.verification_status='verified'
    join public.mela_learning_programs lp on (
      lp.subject_key=any(coalesce(e.subject_areas,'{}'::text[]))
      or lp.subject_title=any(coalesce(e.subject_areas,'{}'::text[]))
    )
    where e.user_id=v_uid and e.verified and e.active
      and (
        lp.subject_key=any(coalesce(t.subjects_taught,'{}'::text[]))
        or lp.subject_title=any(coalesce(t.subjects_taught,'{}'::text[]))
      )
  );
end;
$function$;

;
