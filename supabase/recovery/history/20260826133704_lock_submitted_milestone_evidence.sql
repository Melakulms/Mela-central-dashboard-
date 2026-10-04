-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826133704
CREATE OR REPLACE FUNCTION private.enforce_task_milestone_change()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_contract public.freelance_contracts%rowtype;
  v_system boolean := coalesce(current_setting('mela.system_workflow',true),'')='on' or current_user in ('service_role','postgres');
  v_admin boolean := private.is_admin_user();
  v_other numeric;
begin
  select * into v_contract from public.freelance_contracts where id=coalesce(new.contract_id,old.contract_id);

  if tg_op='INSERT' then
    if not v_system and not v_admin and not private.has_employer_access(v_contract.employer_id,true) then
      raise exception 'only employer team can create milestones';
    end if;
    select coalesce(sum(amount),0) into v_other from public.task_milestones where contract_id=new.contract_id;
    if v_other+new.amount>v_contract.agreed_amount then raise exception 'milestone amounts exceed contract total'; end if;
    new.status:='pending'; new.submitted_at:=null; new.approved_at:=null; new.reviewed_by:=null; new.updated_at:=now();
    return new;
  end if;

  new.updated_at=now();
  if new.id is distinct from old.id or new.contract_id is distinct from old.contract_id or new.created_at is distinct from old.created_at then
    raise exception 'protected milestone fields cannot be changed';
  end if;
  if v_system or v_admin then return new; end if;

  if v_uid=v_contract.freelancer_id then
    if new.title is distinct from old.title or new.description is distinct from old.description or new.amount is distinct from old.amount or new.due_at is distinct from old.due_at or new.milestone_order is distinct from old.milestone_order or new.review_note is distinct from old.review_note or new.reviewed_by is distinct from old.reviewed_by or new.approved_at is distinct from old.approved_at then
      raise exception 'freelancer cannot edit milestone terms/review fields';
    end if;
    if new.status is distinct from old.status then
      if not (old.status in ('pending','in_progress','rejected') and new.status in ('in_progress','submitted')) then
        raise exception 'invalid freelancer milestone transition';
      end if;
      if new.status='submitted' and coalesce(new.deliverable_url,'')='' then
        raise exception 'deliverable_url is required to submit a milestone';
      end if;
      if new.status='submitted' then new.submitted_at=now(); end if;
    else
      -- Once submitted, the freelancer cannot silently replace evidence.
      -- A rejected milestone may be edited and resubmitted.
      if old.status='submitted' and (
        new.deliverable_url is distinct from old.deliverable_url or
        new.submission_note is distinct from old.submission_note or
        new.submitted_at is distinct from old.submitted_at
      ) then
        raise exception 'submitted milestone evidence is locked until employer review';
      end if;
    end if;
    return new;
  end if;

  if private.has_employer_access(v_contract.employer_id,true) then
    if new.deliverable_url is distinct from old.deliverable_url or new.submission_note is distinct from old.submission_note or new.submitted_at is distinct from old.submitted_at then
      raise exception 'employer cannot alter freelancer submission evidence';
    end if;
    if old.status='pending' then
      select coalesce(sum(amount),0) into v_other from public.task_milestones where contract_id=old.contract_id and id<>old.id;
      if v_other+new.amount>v_contract.agreed_amount then raise exception 'milestone amounts exceed contract total'; end if;
    elsif new.title is distinct from old.title or new.description is distinct from old.description or new.amount is distinct from old.amount or new.due_at is distinct from old.due_at or new.milestone_order is distinct from old.milestone_order then
      raise exception 'milestone terms are locked after work starts';
    end if;
    if new.status is distinct from old.status then
      if not (old.status='submitted' and new.status in ('approved','rejected')) then raise exception 'employer may only approve or reject submitted work'; end if;
      if new.status='approved' then
        if not exists(select 1 from public.escrow_transactions e where e.milestone_id=old.id and e.status='held') then raise exception 'escrow must be funded before approval'; end if;
        new.approved_at=now(); new.reviewed_by=v_uid;
      elsif new.status='rejected' then new.reviewed_by=v_uid; end if;
    end if;
    return new;
  end if;
  raise exception 'not authorized';
end;$function$;
;
