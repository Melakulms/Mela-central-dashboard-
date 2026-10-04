-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813103805
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
  v_status text;
  v_contract_id uuid;
  v_freelancer_id uuid;
  v_contract_status text;
  v_employer_id uuid;
  v_url text := nullif(trim(coalesce(p_deliverable_url,'')),'');
  v_row public.task_milestones%rowtype;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if v_url is null then raise exception 'deliverable URL is required'; end if;

  select m.status,m.contract_id
    into v_status,v_contract_id
  from public.task_milestones m
  where m.id=p_milestone_id
  for update;
  if v_status is null then raise exception 'milestone not found'; end if;
  if v_status not in ('pending','in_progress','rejected') then raise exception 'milestone cannot be submitted now: %',v_status; end if;

  select c.freelancer_id,c.status,c.employer_id
    into v_freelancer_id,v_contract_status,v_employer_id
  from public.freelance_contracts c
  where c.id=v_contract_id;
  if v_freelancer_id is null then raise exception 'contract not found'; end if;
  if v_freelancer_id<>v_uid or v_contract_status<>'active' then raise exception 'not authorized or contract inactive'; end if;

  update public.task_milestones
  set deliverable_url=v_url,
      submission_note=nullif(trim(coalesce(p_submission_note,'')),''),
      status='submitted',
      submitted_at=now(),
      updated_at=now()
  where id=p_milestone_id
  returning * into v_row;

  perform private.notify_employer_owner(v_employer_id,'Milestone submitted','A freelancer submitted a milestone for review.','task_milestones',v_row.id);
  return v_row;
end;
$function$;
;
