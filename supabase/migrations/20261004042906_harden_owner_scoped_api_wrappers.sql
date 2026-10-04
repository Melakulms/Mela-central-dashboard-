create or replace function public.activate_my_educator_profile(
  p_partner_org_id uuid,
  p_role_title text default 'Educator'::text,
  p_subject_areas text[] default '{}'::text[],
  p_stage_keys text[] default '{}'::text[]
)
returns public.educator_profiles
language sql
security invoker
set search_path to ''
as $function$
  select * from private.activate_my_educator_profile(p_partner_org_id,p_role_title,p_subject_areas,p_stage_keys);
$function$;

create or replace function public.get_my_arena_creator_analytics(p_days integer default 30)
returns jsonb
language sql
security invoker
set search_path to ''
as $function$ select private.get_my_arena_creator_analytics(p_days); $function$;

create or replace function public.get_my_arena_stats()
returns jsonb
language sql
security invoker
set search_path to ''
as $function$ select private.get_my_arena_stats(); $function$;

create or replace function public.get_my_dashboard_v36()
returns jsonb
language sql
security invoker
set search_path to ''
as $function$ select private.get_my_dashboard_v36(); $function$;

create or replace function public.get_my_guardian_learner_progress(p_learner_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_guardian_learner_progress(p_learner_id); $function$;

create or replace function public.get_my_practice_dashboard()
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_my_practice_dashboard(); $function$;

create or replace function public.get_my_practice_recommendations(p_limit integer default 10)
returns jsonb
language sql
stable
security invoker
set search_path to ''
as $function$ select private.get_my_practice_recommendations(p_limit); $function$;

revoke all on function private.activate_my_educator_profile(uuid,text,text[],text[]) from public, anon;
revoke all on function private.get_my_arena_creator_analytics(integer) from public, anon;
revoke all on function private.get_my_arena_stats() from public, anon;
revoke all on function private.get_my_dashboard_v36() from public, anon;
revoke all on function private.get_guardian_learner_progress(uuid) from public, anon;
revoke all on function private.get_my_practice_dashboard() from public, anon;
revoke all on function private.get_my_practice_recommendations(integer) from public, anon;
grant execute on function private.activate_my_educator_profile(uuid,text,text[],text[]) to authenticated, service_role;
grant execute on function private.get_my_arena_creator_analytics(integer) to authenticated, service_role;
grant execute on function private.get_my_arena_stats() to authenticated, service_role;
grant execute on function private.get_my_dashboard_v36() to authenticated, service_role;
grant execute on function private.get_guardian_learner_progress(uuid) to authenticated, service_role;
grant execute on function private.get_my_practice_dashboard() to authenticated, service_role;
grant execute on function private.get_my_practice_recommendations(integer) to authenticated, service_role;

revoke all on function public.activate_my_educator_profile(uuid,text,text[],text[]) from public, anon;
revoke all on function public.get_my_arena_creator_analytics(integer) from public, anon;
revoke all on function public.get_my_arena_stats() from public, anon;
revoke all on function public.get_my_dashboard_v36() from public, anon;
revoke all on function public.get_my_guardian_learner_progress(uuid) from public, anon;
revoke all on function public.get_my_practice_dashboard() from public, anon;
revoke all on function public.get_my_practice_recommendations(integer) from public, anon;
grant execute on function public.activate_my_educator_profile(uuid,text,text[],text[]) to authenticated, service_role;
grant execute on function public.get_my_arena_creator_analytics(integer) to authenticated, service_role;
grant execute on function public.get_my_arena_stats() to authenticated, service_role;
grant execute on function public.get_my_dashboard_v36() to authenticated, service_role;
grant execute on function public.get_my_guardian_learner_progress(uuid) to authenticated, service_role;
grant execute on function public.get_my_practice_dashboard() to authenticated, service_role;
grant execute on function public.get_my_practice_recommendations(integer) to authenticated, service_role;
