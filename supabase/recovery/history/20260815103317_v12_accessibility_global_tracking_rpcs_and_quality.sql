-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815103317
revoke insert,update,delete on public.external_application_tracking from authenticated;
revoke insert,update,delete on public.external_application_events from authenticated;

create or replace function private.save_my_accessibility_preferences_v12(p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); begin
 if v_uid is null then raise exception 'authentication required'; end if;
 insert into public.learner_accessibility_preferences(
   user_id,narration_enabled,narration_rate,narration_language,screen_reader_mode,keyboard_only,high_contrast,text_scale,reduced_motion,captions_enabled,simplified_language,extended_time_multiplier,large_targets,color_independent_mode,preference_note)
 values(
   v_uid,coalesce((p->>'narration_enabled')::boolean,false),coalesce((p->>'narration_rate')::numeric,1),coalesce(nullif(p->>'narration_language',''),'en'),coalesce((p->>'screen_reader_mode')::boolean,false),coalesce((p->>'keyboard_only')::boolean,false),coalesce((p->>'high_contrast')::boolean,false),coalesce((p->>'text_scale')::numeric,1),coalesce((p->>'reduced_motion')::boolean,false),coalesce((p->>'captions_enabled')::boolean,true),coalesce((p->>'simplified_language')::boolean,false),coalesce((p->>'extended_time_multiplier')::numeric,1),coalesce((p->>'large_targets')::boolean,false),coalesce((p->>'color_independent_mode')::boolean,false),nullif(p->>'preference_note',''))
 on conflict(user_id) do update set narration_enabled=excluded.narration_enabled,narration_rate=excluded.narration_rate,narration_language=excluded.narration_language,screen_reader_mode=excluded.screen_reader_mode,keyboard_only=excluded.keyboard_only,high_contrast=excluded.high_contrast,text_scale=excluded.text_scale,reduced_motion=excluded.reduced_motion,captions_enabled=excluded.captions_enabled,simplified_language=excluded.simplified_language,extended_time_multiplier=excluded.extended_time_multiplier,large_targets=excluded.large_targets,color_independent_mode=excluded.color_independent_mode,preference_note=excluded.preference_note,updated_at=now();
 return (select to_jsonb(a)-'user_id'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid);
end $$;
revoke all on function private.save_my_accessibility_preferences_v12(jsonb) from public,anon,authenticated;
grant execute on function private.save_my_accessibility_preferences_v12(jsonb) to authenticated,service_role;

create or replace function public.save_my_accessibility_preferences_v12(p jsonb)
returns jsonb language sql security invoker set search_path='' as $$select private.save_my_accessibility_preferences_v12(p);$$;
revoke all on function public.save_my_accessibility_preferences_v12(jsonb) from public,anon;
grant execute on function public.save_my_accessibility_preferences_v12(jsonb) to authenticated,service_role;

create or replace function public.get_my_accessibility_preferences_v12()
returns jsonb language plpgsql stable security invoker set search_path='' as $$declare v_uid uuid:=(select auth.uid()); begin if v_uid is null then raise exception 'authentication required'; end if; return coalesce((select to_jsonb(a)-'user_id'-'created_at'-'updated_at' from public.learner_accessibility_preferences a where a.user_id=v_uid),'{}'::jsonb); end $$;
revoke all on function public.get_my_accessibility_preferences_v12() from public,anon;
grant execute on function public.get_my_accessibility_preferences_v12() to authenticated,service_role;

create or replace function public.get_global_opportunity_sources_v12(p_country_code text default null,p_source_type text default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$begin
 if (select auth.uid()) is null then raise exception 'authentication required'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'country_code',country_code,'country_name',country_name,'region',region,'income_group',income_group,'source_type',source_type,'source_name',source_name,'ownership_type',ownership_type,'base_url',base_url,'application_url',application_url,'canonical_domain',canonical_domain,'supports_external_apply',supports_external_apply,'supports_status_api',supports_status_api,'supports_sso',supports_sso,'verification_status',verification_status,'evidence_note',evidence_note) order by country_name,source_type,source_name) from public.global_opportunity_sources where active and verification_status='verified' and (p_country_code is null or country_code=upper(p_country_code)) and (p_source_type is null or source_type=p_source_type)),'[]'::jsonb);
end $$;
revoke all on function public.get_global_opportunity_sources_v12(text,text) from public,anon;
grant execute on function public.get_global_opportunity_sources_v12(text,text) to authenticated,service_role;

create or replace function private.create_external_application_v12(p_source_id uuid,p_external_title text,p_institution_name text,p_application_type text,p_external_url text,p_external_reference text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid; v_src public.global_opportunity_sources%rowtype; v_host_re text; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if nullif(trim(coalesce(p_external_title,'')),'') is null then raise exception 'title required'; end if;
 if p_application_type not in ('university','college','job','internship','scholarship','training','other') then raise exception 'invalid application type'; end if;
 if p_external_url !~* '^https://' then raise exception 'https external url required'; end if;
 if p_source_id is not null then
   select * into v_src from public.global_opportunity_sources where id=p_source_id and active and verification_status='verified';
   if not found then raise exception 'verified source required'; end if;
   v_host_re := '^[a-z]+://([^/]*\.)?' || replace(v_src.canonical_domain,'.','\.') || '(/|$)';
   if lower(p_external_url) !~ v_host_re then raise exception 'external url must match verified source domain'; end if;
 end if;
 insert into public.external_application_tracking(user_id,source_id,external_title,institution_name,country_code,application_type,external_url,external_reference,status,notes)
 values(v_uid,p_source_id,trim(p_external_title),nullif(trim(coalesce(p_institution_name,'')),''),case when p_source_id is null then null else v_src.country_code end,p_application_type,p_external_url,nullif(trim(coalesce(p_external_reference,'')),''),'saved',nullif(trim(coalesce(p_notes,'')),'')) returning id into v_id;
 insert into public.external_application_events(application_id,user_id,event_type,new_status,note) values(v_id,v_uid,'created','saved','Application tracker created in Mela; external status is manual unless the source has a verified API integration.');
 return v_id;
end $$;
revoke all on function private.create_external_application_v12(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function private.create_external_application_v12(uuid,text,text,text,text,text,text) to authenticated,service_role;

create or replace function public.create_external_application_v12(p_source_id uuid,p_external_title text,p_institution_name text,p_application_type text,p_external_url text,p_external_reference text default null,p_notes text default null)
returns uuid language sql security invoker set search_path='' as $$select private.create_external_application_v12(p_source_id,p_external_title,p_institution_name,p_application_type,p_external_url,p_external_reference,p_notes);$$;
revoke all on function public.create_external_application_v12(uuid,text,text,text,text,text,text) from public,anon;
grant execute on function public.create_external_application_v12(uuid,text,text,text,text,text,text) to authenticated,service_role;

create or replace function private.update_external_application_status_v12(p_application_id uuid,p_status text,p_note text default null,p_external_reference text default null,p_next_action_at timestamptz default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_old text; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if p_status not in ('saved','preparing','submitted','assessment','interview','offer','accepted','rejected','withdrawn','closed') then raise exception 'invalid status'; end if;
 select status into v_old from public.external_application_tracking where id=p_application_id and user_id=v_uid for update;
 if not found then raise exception 'application tracker not found'; end if;
 update public.external_application_tracking set status=p_status,external_reference=coalesce(nullif(trim(coalesce(p_external_reference,'')),''),external_reference),next_action_at=p_next_action_at,applied_at=case when p_status in ('submitted','assessment','interview','offer','accepted','rejected') then coalesce(applied_at,now()) else applied_at end,last_checked_at=now(),notes=case when nullif(trim(coalesce(p_note,'')),'') is null then notes else concat_ws(E'\n',notes,trim(p_note)) end,updated_at=now() where id=p_application_id;
 if v_old is distinct from p_status then insert into public.external_application_events(application_id,user_id,event_type,old_status,new_status,note) values(p_application_id,v_uid,'status_changed',v_old,p_status,nullif(trim(coalesce(p_note,'')),'')); elsif nullif(trim(coalesce(p_note,'')),'') is not null then insert into public.external_application_events(application_id,user_id,event_type,old_status,new_status,note) values(p_application_id,v_uid,'note_added',v_old,p_status,trim(p_note)); end if;
 return (select to_jsonb(a)-'user_id' from public.external_application_tracking a where a.id=p_application_id);
end $$;
revoke all on function private.update_external_application_status_v12(uuid,text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function private.update_external_application_status_v12(uuid,text,text,text,timestamptz) to authenticated,service_role;

create or replace function public.update_external_application_status_v12(p_application_id uuid,p_status text,p_note text default null,p_external_reference text default null,p_next_action_at timestamptz default null)
returns jsonb language sql security invoker set search_path='' as $$select private.update_external_application_status_v12(p_application_id,p_status,p_note,p_external_reference,p_next_action_at);$$;
revoke all on function public.update_external_application_status_v12(uuid,text,text,text,timestamptz) from public,anon;
grant execute on function public.update_external_application_status_v12(uuid,text,text,text,timestamptz) to authenticated,service_role;

create or replace function public.get_my_external_applications_v12()
returns jsonb language plpgsql stable security invoker set search_path='' as $$declare v_uid uuid:=(select auth.uid()); begin if v_uid is null then raise exception 'authentication required'; end if; return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'source_id',a.source_id,'external_title',a.external_title,'institution_name',a.institution_name,'country_code',a.country_code,'application_type',a.application_type,'external_url',a.external_url,'external_reference',a.external_reference,'status',a.status,'applied_at',a.applied_at,'next_action_at',a.next_action_at,'last_checked_at',a.last_checked_at,'notes',a.notes,'created_at',a.created_at,'updated_at',a.updated_at,'events',coalesce((select jsonb_agg(to_jsonb(e)-'user_id' order by e.created_at desc) from public.external_application_events e where e.application_id=a.id),'[]'::jsonb)) order by a.updated_at desc) from public.external_application_tracking a where a.user_id=v_uid),'[]'::jsonb); end $$;
revoke all on function public.get_my_external_applications_v12() from public,anon;
grant execute on function public.get_my_external_applications_v12() to authenticated,service_role;

insert into public.content_accessibility_metadata(content_type,content_id,narration_text,easy_read_summary,alt_text,accessibility_review_status,metadata)
select 'chapter',c.id::text,'Chapter '||c.chapter_number||'. '||c.title||'. '||coalesce(nullif(c.description,''),'Open the chapter to study the mapped learning outcomes.'),left(coalesce(nullif(c.description,''),'Study the chapter step by step, practice, then check understanding.'),500),'Text chapter: '||c.title,'machine_ready',jsonb_build_object('screen_reader_ready',true,'narration_ready',true,'human_review_required',true)
from public.mela_learning_chapters c where c.status='published'
on conflict(content_type,content_id) do update set narration_text=excluded.narration_text,easy_read_summary=excluded.easy_read_summary,alt_text=excluded.alt_text,metadata=excluded.metadata,updated_at=now();

insert into public.content_accessibility_metadata(content_type,content_id,narration_text,easy_read_summary,alt_text,accessibility_review_status,metadata)
select 'material',m.id::text,m.title||'. '||coalesce(nullif(m.summary,''),'Learning material.'),left(coalesce(nullif(m.summary,''),'Open this material and follow the learning activity.'),500),'Learning material: '||m.title,'machine_ready',jsonb_build_object('screen_reader_ready',true,'narration_ready',true,'low_bandwidth_ready',m.low_bandwidth_ready,'human_review_required',true)
from public.mela_learning_chapter_materials m where m.status='published'
on conflict(content_type,content_id) do update set narration_text=excluded.narration_text,easy_read_summary=excluded.easy_read_summary,alt_text=excluded.alt_text,metadata=excluded.metadata,updated_at=now();

update public.mela_question_review_batches b set target_question_count=800,generated_question_count=x.n,deterministic_validated_count=x.det_n,educator_verified_count=x.edu_n,review_status=case when x.edu_n>=800 then 'educator_verified' else 'generated_pending_educator_review' end,updated_at=now()
from (select program_key,count(*) n,count(*) filter(where validation_status='deterministic_validated') det_n,count(*) filter(where validation_status='educator_verified') edu_n from public.mela_question_bank where active group by program_key) x where b.program_key=x.program_key;

insert into public.platform_launch_requirements(requirement_key,category,title,requirement_type,required,manual_status,evidence_note)
values
('accessibility_human_review','Accessibility','Accessibility and assistive-technology review passed with disabled learners','manual',true,'pending','v12 adds narration, keyboard/screen-reader preferences, high contrast, text scaling, reduced motion, extended-time compatibility and accessible content metadata. Human testing with disabled learners and hosted assistive-technology QA is still required.'),
('global_source_reverification','Global Opportunities','50-country university/work source network periodically reverified','manual',true,'pending','Source catalog is being built from verified official/institutional domains. Reverification and stale-link monitoring must pass before public launch.')
on conflict(requirement_key) do update set title=excluded.title,category=excluded.category,required=true,manual_status='pending',evidence_note=excluded.evidence_note,updated_at=now();

update public.platform_launch_requirements set evidence_note='v12 contains 100,800 active Grade 1–12 questions with 800 per program, private server-side grading for all 100,800 and multiple response types. Machine structural QA is required, but educator_verified remains a human gate; do not market the whole bank as teacher-certified until qualified review is recorded.',updated_at=now() where requirement_key='question_bank_educator_review';
;
