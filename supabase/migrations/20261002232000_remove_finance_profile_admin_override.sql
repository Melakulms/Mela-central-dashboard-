-- Financial transfer claims are user/employer operations, not an administrator
-- impersonation surface. Administrative finance workflows use mela-admin-api and
-- its audit/RBAC boundary instead.
create or replace function public.claim_mela_payout(p_payout_id uuid,p_actor uuid) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare p public.payout_requests%rowtype; m public.task_milestones%rowtype; c public.freelance_contracts%rowtype; e public.escrow_transactions%rowtype;
begin
 if not public.platform_feature_available('payouts') then raise exception 'Payout initiation disabled' using errcode='42501'; end if;
 select * into p from public.payout_requests where id=p_payout_id;
 if not found then raise exception 'Payout not found'; end if;
 select * into m from public.task_milestones where id=p.milestone_id for update;
 select * into p from public.payout_requests where id=p_payout_id for update;
 if p.status<>'pending' then return null; end if;
 if m.status<>'approved' then raise exception 'Approved milestone required'; end if;
 select * into c from public.freelance_contracts where id=m.contract_id;
 if not exists(select 1 from public.profiles u where u.id=p_actor and u.account_status='active' and u.deleted_at is null and (u.email_verified or u.phone_verified)) then raise exception 'Active verified actor required' using errcode='42501'; end if;
 if not exists(select 1 from public.employers co where co.id=c.employer_id and co.owner_id=p_actor and co.verified and co.verification_status='verified')
 and not exists(select 1 from public.employer_members em join public.employers co on co.id=em.employer_id where em.employer_id=c.employer_id and em.user_id=p_actor and em.status='active' and em.member_role in ('admin','hiring_manager','recruiter') and co.verified and co.verification_status='verified') then raise exception 'Payout authority required' using errcode='42501'; end if;
 select * into e from public.escrow_transactions where id=p.escrow_id for update;
 if e.status is distinct from 'held' or e.milestone_id is distinct from m.id or e.contract_id is distinct from c.id or e.amount_minor is distinct from p.amount_minor or p.freelancer_id is distinct from c.freelancer_id or e.currency is distinct from p.currency then raise exception 'Payout does not match funded milestone'; end if;
 if exists(select 1 from public.payout_requests other where other.milestone_id=m.id and other.id<>p.id and other.status in ('queued','success')) then raise exception 'Milestone already has a claimed payout'; end if;
 update public.payout_requests set status='queued',updated_at=now(),failure_reason=null where id=p.id returning * into p;
 insert into admin.audit_log(actor_user_id,action,target_schema,target_table,target_id,before_data,after_data,metadata)
 values(p_actor,'payout.claim','public','payout_requests',p.id::text,jsonb_build_object('status','pending'),to_jsonb(p),jsonb_build_object('source','mela-finance'));
 return to_jsonb(p);
end;
$$;
revoke all on function public.claim_mela_payout(uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_mela_payout(uuid,uuid) to service_role;
