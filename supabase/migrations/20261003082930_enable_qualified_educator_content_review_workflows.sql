create table if not exists private.mela_chapter_review_decisions (
  id bigint generated always as identity primary key,
  queue_id uuid not null references public.mela_chapter_review_queue(id) on delete cascade,
  chapter_id uuid not null references public.mela_learning_chapters(id) on delete cascade,
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  decision text not null check (decision in ('approved','needs_changes','blocked_source')),
  note text not null check (char_length(btrim(note)) between 5 and 4000),
  reviewed_at timestamptz not null default now()
);

alter table private.mela_chapter_review_decisions enable row level security;
revoke all on table private.mela_chapter_review_decisions from public, anon, authenticated;
create index if not exists mela_chapter_review_decisions_queue_reviewed_idx on private.mela_chapter_review_decisions(queue_id, reviewed_at desc);
create index if not exists mela_chapter_review_decisions_reviewer_idx on private.mela_chapter_review_decisions(reviewer_id, reviewed_at desc);

create or replace function private.get_chapter_review_queue(
  p_program_key text default null,
  p_status text default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_limit integer := least(greatest(coalesce(p_limit,50),1),100);
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_status is not null and p_status not in ('pending','in_progress','approved','needs_changes','blocked_source') then
    raise exception 'invalid review status';
  end if;

  return jsonb_build_object(
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'queue_id', z.id,
        'chapter_id', z.chapter_id,
        'program_key', z.program_key,
        'grade_level', z.grade_level,
        'subject_key', z.subject_key,
        'chapter_number', z.chapter_number,
        'chapter_title', z.chapter_title,
        'source_state', z.source_state,
        'review_type', z.review_type,
        'priority', z.priority,
        'status', z.status,
        'assigned_to_me', z.assigned_to = v_uid,
        'assigned', z.assigned_to is not null,
        'assigned_at', z.assigned_at,
        'reviewed_at', z.reviewed_at,
        'reviewer_requirement', z.reviewer_requirement
      ) order by z.priority asc, z.grade_level asc, z.subject_key asc, z.chapter_number asc)
      from (
        select q.*
        from public.mela_chapter_review_queue q
        where (p_program_key is null or q.program_key=p_program_key)
          and (p_status is null or q.status=p_status)
          and private.question_reviewer_allowed_v18(v_uid,q.program_key)
        order by q.priority asc,q.grade_level asc,q.subject_key asc,q.chapter_number asc
        limit v_limit
      ) z
    ),'[]'::jsonb),
    'summary', coalesce((
      select jsonb_build_object(
        'eligible_total', count(*),
        'pending', count(*) filter(where q.status='pending'),
        'in_progress', count(*) filter(where q.status='in_progress'),
        'approved', count(*) filter(where q.status='approved'),
        'needs_changes', count(*) filter(where q.status='needs_changes'),
        'blocked_source', count(*) filter(where q.status='blocked_source'),
        'assigned_to_me', count(*) filter(where q.assigned_to=v_uid)
      )
      from public.mela_chapter_review_queue q
      where (p_program_key is null or q.program_key=p_program_key)
        and private.question_reviewer_allowed_v18(v_uid,q.program_key)
    ),'{}'::jsonb)
  );
end;
$function$;

create or replace function private.get_chapter_review_item(p_queue_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  q public.mela_chapter_review_queue%rowtype;
  c public.mela_learning_chapters%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into q from public.mela_chapter_review_queue where id=p_queue_id;
  if not found then raise exception 'chapter review task not found'; end if;
  if not private.question_reviewer_allowed_v18(v_uid,q.program_key) then raise exception 'verified educator subject access required'; end if;
  select * into c from public.mela_learning_chapters where id=q.chapter_id;
  if not found then raise exception 'chapter not found'; end if;

  return jsonb_build_object(
    'task', jsonb_build_object(
      'queue_id',q.id,'chapter_id',q.chapter_id,'program_key',q.program_key,'grade_level',q.grade_level,
      'subject_key',q.subject_key,'chapter_number',q.chapter_number,'chapter_title',q.chapter_title,
      'source_state',q.source_state,'review_type',q.review_type,'priority',q.priority,'status',q.status,
      'reviewer_requirement',q.reviewer_requirement,'assigned_to_me',q.assigned_to=v_uid,
      'assigned',q.assigned_to is not null,'assigned_at',q.assigned_at,'reviewed_at',q.reviewed_at,
      'reviewer_note',case when q.assigned_to=v_uid or private.is_admin_user() then q.reviewer_note else null end
    ),
    'chapter', jsonb_build_object(
      'chapter_key',c.chapter_key,'chapter_number',c.chapter_number,'title',c.title,'title_local',c.title_local,
      'description',c.description,'learning_outcomes',c.learning_outcomes,'source_name',c.source_name,
      'source_url',c.source_url,'source_kind',c.source_kind,'source_verified',c.source_verified,
      'official_alignment_status',c.official_alignment_status,'status',c.status
    ),
    'topics', coalesce((select jsonb_agg(jsonb_build_object(
      'id',t.id,'topic_number',t.topic_number,'title',t.title,'title_local',t.title_local,
      'description',t.description,'learning_objectives',t.learning_objectives,'source_verified',t.source_verified,'status',t.status
    ) order by t.display_order,t.topic_number) from public.mela_learning_chapter_topics t where t.chapter_id=q.chapter_id),'[]'::jsonb),
    'materials', coalesce((select jsonb_agg(jsonb_build_object(
      'id',m.id,'topic_id',m.topic_id,'material_key',m.material_key,'material_type',m.material_type,
      'title',m.title,'summary',m.summary,'pedagogical_role',m.pedagogical_role,'language_code',m.language_code,
      'access_tier',m.access_tier,'estimated_minutes',m.estimated_minutes,'downloadable',m.downloadable,
      'low_bandwidth_ready',m.low_bandwidth_ready,'status',m.status,'editorial_status',m.editorial_status
    ) order by m.display_order,m.title) from public.mela_learning_chapter_materials m where m.chapter_id=q.chapter_id),'[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object('decision',d.decision,'note',d.note,'reviewed_at',d.reviewed_at) order by d.reviewed_at desc)
      from private.mela_chapter_review_decisions d where d.queue_id=q.id),'[]'::jsonb)
  );
end;
$function$;

create or replace function private.claim_chapter_review(p_queue_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  q public.mela_chapter_review_queue%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  select * into q from public.mela_chapter_review_queue where id=p_queue_id for update;
  if not found then raise exception 'chapter review task not found'; end if;
  if not private.question_reviewer_allowed_v18(v_uid,q.program_key) then raise exception 'verified educator subject access required'; end if;
  if q.status='approved' then raise exception 'approved review task is closed'; end if;
  if q.assigned_to is not null and q.assigned_to<>v_uid then raise exception 'review task already assigned'; end if;

  update public.mela_chapter_review_queue
  set assigned_to=v_uid,
      assigned_at=coalesce(assigned_at,now()),
      status='in_progress',
      updated_at=now()
  where id=q.id;

  return jsonb_build_object('queue_id',q.id,'status','in_progress','assigned_to_me',true);
end;
$function$;

create or replace function private.submit_chapter_review(p_queue_id uuid,p_decision text,p_note text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  q public.mela_chapter_review_queue%rowtype;
  v_note text := btrim(coalesce(p_note,''));
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if p_decision not in ('approved','needs_changes','blocked_source') then raise exception 'invalid review decision'; end if;
  if char_length(v_note)<5 or char_length(v_note)>4000 then raise exception 'review note must be 5-4000 characters'; end if;

  select * into q from public.mela_chapter_review_queue where id=p_queue_id for update;
  if not found then raise exception 'chapter review task not found'; end if;
  if not private.question_reviewer_allowed_v18(v_uid,q.program_key) then raise exception 'verified educator subject access required'; end if;
  if q.assigned_to is null then raise exception 'claim review task before submitting'; end if;
  if q.assigned_to<>v_uid then raise exception 'review task is assigned to another reviewer'; end if;

  insert into private.mela_chapter_review_decisions(queue_id,chapter_id,reviewer_id,decision,note)
  values(q.id,q.chapter_id,v_uid,p_decision,v_note);

  update public.mela_chapter_review_queue
  set status=p_decision,
      reviewer_note=v_note,
      reviewed_at=now(),
      updated_at=now()
  where id=q.id;

  return jsonb_build_object('queue_id',q.id,'chapter_id',q.chapter_id,'status',p_decision,'reviewed_at',now());
end;
$function$;

revoke all on function private.get_chapter_review_queue(text,text,integer) from public,anon;
revoke all on function private.get_chapter_review_item(uuid) from public,anon;
revoke all on function private.claim_chapter_review(uuid) from public,anon;
revoke all on function private.submit_chapter_review(uuid,text,text) from public,anon;
grant execute on function private.get_chapter_review_queue(text,text,integer) to authenticated,service_role;
grant execute on function private.get_chapter_review_item(uuid) to authenticated,service_role;
grant execute on function private.claim_chapter_review(uuid) to authenticated,service_role;
grant execute on function private.submit_chapter_review(uuid,text,text) to authenticated,service_role;

create or replace function public.get_chapter_review_queue(p_program_key text default null,p_status text default null,p_limit integer default 50)
returns jsonb language sql stable security invoker set search_path to '' as $function$
select private.get_chapter_review_queue(p_program_key,p_status,p_limit);
$function$;
create or replace function public.get_chapter_review_item(p_queue_id uuid)
returns jsonb language sql stable security invoker set search_path to '' as $function$
select private.get_chapter_review_item(p_queue_id);
$function$;
create or replace function public.claim_chapter_review(p_queue_id uuid)
returns jsonb language sql security invoker set search_path to '' as $function$
select private.claim_chapter_review(p_queue_id);
$function$;
create or replace function public.submit_chapter_review(p_queue_id uuid,p_decision text,p_note text)
returns jsonb language sql security invoker set search_path to '' as $function$
select private.submit_chapter_review(p_queue_id,p_decision,p_note);
$function$;

revoke all on function public.get_chapter_review_queue(text,text,integer) from public,anon;
revoke all on function public.get_chapter_review_item(uuid) from public,anon;
revoke all on function public.claim_chapter_review(uuid) from public,anon;
revoke all on function public.submit_chapter_review(uuid,text,text) from public,anon;
grant execute on function public.get_chapter_review_queue(text,text,integer) to authenticated,service_role;
grant execute on function public.get_chapter_review_item(uuid) to authenticated,service_role;
grant execute on function public.claim_chapter_review(uuid) to authenticated,service_role;
grant execute on function public.submit_chapter_review(uuid,text,text) to authenticated,service_role;

create or replace function public.review_question_slice_v18(p_slice_id bigint,p_decisions jsonb)
returns jsonb language sql security invoker set search_path to '' as $function$
select private.review_question_slice_v18(p_slice_id,p_decisions);
$function$;
revoke all on function private.review_question_slice_v18(bigint,jsonb) from public,anon;
grant execute on function private.review_question_slice_v18(bigint,jsonb) to authenticated,service_role;
revoke all on function public.review_question_slice_v18(bigint,jsonb) from public,anon;
grant execute on function public.review_question_slice_v18(bigint,jsonb) to authenticated,service_role;
