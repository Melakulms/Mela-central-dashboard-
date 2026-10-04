-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815170313
create or replace function public.release_question_generation_target_v18(p_target_question_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$ begin
 update private.mela_question_replacement_targets_v18 set status='queued',updated_at=now() where target_question_id=p_target_question_id and status='generating';
 return found; end $$;
revoke all on function public.release_question_generation_target_v18(uuid) from public,anon,authenticated;
grant execute on function public.release_question_generation_target_v18(uuid) to service_role;

create or replace function public.get_question_generation_usage_v18()
returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('generated_24h',count(*) filter(where generated_at>now()-interval '24 hours'),'generated_total',count(*),'approved_total',count(*) filter(where status='educator_approved'),'promoted_total',count(*) filter(where status='promoted')) from private.mela_question_generation_candidates_v18;
$$;
revoke all on function public.get_question_generation_usage_v18() from public,anon,authenticated;
grant execute on function public.get_question_generation_usage_v18() to service_role;
;
