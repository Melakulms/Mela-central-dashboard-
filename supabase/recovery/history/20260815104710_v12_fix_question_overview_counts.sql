-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815104710
create or replace function public.get_my_question_bank_overview_v12()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 return jsonb_build_object(
  'programs',coalesce((select jsonb_agg(jsonb_build_object(
    'program_key',p.program_key,'grade_level',p.grade_level,'track_key',p.track_key,'subject_title',p.subject_title,
    'question_count',x.n,'free_count',x.free_n,'subscription_count',x.sub_n,'paid_pack_count',x.one_n,'types',x.types,
    'stats',coalesce(to_jsonb(s)-'user_id'-'program_key'-'created_at'-'updated_at','{}'::jsonb)
  ) order by p.grade_level,p.display_order,p.subject_title)
   from public.mela_learning_programs p
   join lateral (
     select count(*) n,
            count(*) filter(where access_tier='free') free_n,
            count(*) filter(where access_tier='subscription') sub_n,
            count(*) filter(where access_tier='one_time') one_n,
            coalesce((select jsonb_object_agg(question_type,cnt order by question_type) from (select question_type,count(*) cnt from public.mela_question_bank tq where tq.program_key=p.program_key and tq.active group by question_type) tt),'{}'::jsonb) types
     from public.mela_question_bank q where q.program_key=p.program_key and q.active
   ) x on true
   left join public.mela_question_user_program_stats s on s.program_key=p.program_key and s.user_id=v_uid
   where p.program_kind='school_subject' and p.grade_level between 1 and 12 and p.active),'[]'::jsonb),
  'accessibility',coalesce((select to_jsonb(a)-'user_id'-'preference_note'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid),'{}'::jsonb)
 );
end; $$;
revoke all on function public.get_my_question_bank_overview_v12() from public,anon;
grant execute on function public.get_my_question_bank_overview_v12() to authenticated,service_role;
;
