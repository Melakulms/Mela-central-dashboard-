-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170945
create or replace function public.can_review_questions_v18()
returns boolean language plpgsql stable security definer set search_path=''
as $$ declare v_uid uuid:=(select auth.uid()); begin
 if v_uid is null then return false; end if;
 return exists(select 1 from public.profiles p where p.id=v_uid and p.role='admin') or exists(select 1 from public.educator_profiles e where e.user_id=v_uid and e.verified and e.active);
end $$;
revoke all on function public.can_review_questions_v18() from public,anon;
grant execute on function public.can_review_questions_v18() to authenticated;
;
