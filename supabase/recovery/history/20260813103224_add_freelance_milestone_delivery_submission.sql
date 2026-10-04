-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813103224
create or replace function private.submit_task_milestone_with_delivery(
  p_milestone_id uuid,
  p_deliverable_url text,
  p_submission_note text default null::text
)
returns public.task_milestones
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := (select auth.uid());
  v_m public.task_milestones%rowtype;
  v_c public.freelance_contracts%rowtype;
  v_url text := nullif(trim(coalesce(p_deliverable_url,'')),'');
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_url is null then raise exception 'deliverable URL is required'; end if;

  select * into v_m from public.task_milestones where id=p_milestone_id for update;
  if not found then raise exception 'milestone not found'; end if;
  select * into v_c from public.freelance_contracts where id=v_m.contract_id;
  if v_c.freelancer_id<>v_uid or v_c.status<>'active' then raise exception 'not authorized or contract inactive'; end if;
  if v_m.status not in ('pending','in_progress','rejected') then raise exception 'milestone cannot be submitted now'; end if;

  update public.task_milestones
  set deliverable_url=v_url,
      submission_note=nullif(trim(coalesce(p_submission_note,'')),''),
      status='submitted',
      submitted_at=now(),
      updated_at=now()
  where id=p_milestone_id
  returning * into v_m;

  perform private.notify_employer_owner(v_c.employer_id,'Milestone submitted','A freelancer submitted a milestone for review.','task_milestones',v_m.id);
  return v_m;
end;
$function$;

create or replace function public.submit_task_milestone_with_delivery(
  p_milestone_id uuid,
  p_deliverable_url text,
  p_submission_note text default null::text
)
returns public.task_milestones
language sql
set search_path to ''
as $function$
  select (private.submit_task_milestone_with_delivery(p_milestone_id,p_deliverable_url,p_submission_note)).*
$function$;

revoke all on function private.submit_task_milestone_with_delivery(uuid,text,text) from public,anon;
grant execute on function private.submit_task_milestone_with_delivery(uuid,text,text) to authenticated,service_role;
revoke all on function public.submit_task_milestone_with_delivery(uuid,text,text) from public,anon;
grant execute on function public.submit_task_milestone_with_delivery(uuid,text,text) to authenticated,service_role;
;
