-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814163842
create table if not exists public.platform_launch_requirements (
  requirement_key text primary key,
  category text not null,
  title text not null,
  requirement_type text not null check (requirement_type in ('manual','auto','conditional')),
  required boolean not null default true,
  manual_status text not null default 'pending' check (manual_status in ('pending','complete','blocked','not_required')),
  evidence_note text,
  evidence_url text,
  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.platform_launch_requirements enable row level security;
revoke all on table public.platform_launch_requirements from anon,authenticated;
grant select on table public.platform_launch_requirements to authenticated;

create policy platform_launch_requirements_admin_read
on public.platform_launch_requirements for select to authenticated
using (private.is_admin_user());

insert into public.platform_launch_requirements(requirement_key,category,title,requirement_type,required,manual_status) values
('leaked_password_protection','Security','Supabase leaked-password protection enabled','manual',true,'blocked'),
('custom_smtp','Authentication','Production custom SMTP configured and tested','manual',true,'pending'),
('email_recovery','Authentication','Email confirmation and password-recovery redirect tested','manual',true,'pending'),
('google_oauth','Authentication','Google OAuth configured if included at launch','manual',false,'not_required'),
('sms_otp','Authentication','SMS OTP configured if included at launch','manual',false,'not_required'),
('assessment_translation_certification','Languages','All four translated credential assessment sets certified','auto',true,'pending'),
('real_employer_supply','Marketplace','At least 3 real verified employers','auto',true,'pending'),
('real_opportunity_supply','Marketplace','At least 10 real open verified opportunities','auto',true,'pending'),
('real_freelance_supply','Marketplace','At least 5 real open freelance tasks','auto',true,'pending'),
('real_scholarship_supply','Marketplace','At least 5 real verified scholarship records','auto',true,'pending'),
('eca_registration','Legal','ECA data-protection registration/compliance completed','manual',true,'pending'),
('cross_border_register','Legal','Cross-border processor register and safeguards documented','manual',true,'pending'),
('legal_review','Legal','Qualified Ethiopian legal review completed','manual',true,'pending'),
('payments_provider','Payments','Chapa provider checkout/callback/idempotency/reconciliation verified','conditional',true,'pending'),
('payout_provider','Payments','KYC and payout provider flow verified','conditional',true,'pending'),
('video_provider','Realtime','Production WebRTC STUN/TURN and device calls verified','conditional',true,'pending'),
('staging_verified','Deployment','Hosted Preview/Staging end-to-end verification passed','manual',true,'pending'),
('observability','Operations','Error tracking, logs and operational alerts verified','manual',true,'pending'),
('backup_restore','Operations','Backup/restore rehearsal passed','manual',true,'pending'),
('load_test','Scale','Load/concurrency test plan passed','manual',true,'pending'),
('device_matrix','QA','Mobile and desktop browser/accessibility matrix passed','manual',true,'pending'),
('slow_network','QA','Slow Ethiopian mobile-network experience verified','manual',true,'pending'),
('rls_all_public','Security','RLS enabled on every public table','auto',true,'pending'),
('no_public_security_definers','Security','No public SECURITY DEFINER API exposure','auto',true,'pending')
on conflict(requirement_key) do update set category=excluded.category,title=excluded.title,requirement_type=excluded.requirement_type,required=excluded.required,updated_at=now();

create or replace function private.get_platform_launch_readiness()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=(select auth.uid());
  v_items jsonb;
  v_required int;
  v_satisfied int;
  v_real_employers int;
  v_real_opps int;
  v_real_tasks int;
  v_real_scholarships int;
  v_translated_certified int;
  v_public_tables int;
  v_rls_tables int;
  v_public_definers int;
begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;

  select count(*) into v_real_employers
  from public.employers e join public.profiles p on p.id=e.owner_id
  where e.verified=true and e.verification_status='verified' and coalesce(p.email,'') not like '%@mela.invalid';

  select count(*) into v_real_opps
  from public.opportunities o left join public.profiles p on p.id=o.posted_by
  where o.status='open' and o.verified_active=true and coalesce(p.email,'') not like '%@mela.invalid';

  select count(*) into v_real_tasks
  from public.marketplace_tasks t left join public.profiles p on p.id=t.posted_by
  where t.status='open' and coalesce(p.email,'') not like '%@mela.invalid';

  select count(*) into v_real_scholarships
  from public.opportunities o left join public.profiles p on p.id=o.posted_by
  where o.opportunity_type='scholarships'::public.opportunity_type and o.status='open' and o.verified_active=true and coalesce(p.email,'') not like '%@mela.invalid';

  select count(*) into v_translated_certified
  from public.assessment_language_certifications c
  where c.language_code in ('am','om','ti','so') and c.status='certified';

  select count(*)::int,count(*) filter(where c.relrowsecurity)::int into v_public_tables,v_rls_tables
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r';

  select count(*)::int into v_public_definers
  from pg_catalog.pg_proc p join pg_catalog.pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.prosecdef
    and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('authenticated',p.oid,'EXECUTE'));

  with derived as (
    select r.*,
      case r.requirement_key
        when 'assessment_translation_certification' then case when v_translated_certified>=32 then 'complete' else 'pending' end
        when 'real_employer_supply' then case when v_real_employers>=3 then 'complete' else 'pending' end
        when 'real_opportunity_supply' then case when v_real_opps>=10 then 'complete' else 'pending' end
        when 'real_freelance_supply' then case when v_real_tasks>=5 then 'complete' else 'pending' end
        when 'real_scholarship_supply' then case when v_real_scholarships>=5 then 'complete' else 'pending' end
        when 'rls_all_public' then case when v_public_tables=v_rls_tables then 'complete' else 'blocked' end
        when 'no_public_security_definers' then case when v_public_definers=0 then 'complete' else 'blocked' end
        when 'payments_provider' then case when not public.platform_feature_available('payments') then 'not_required' else r.manual_status end
        when 'payout_provider' then case when not public.platform_feature_available('payouts') then 'not_required' else r.manual_status end
        when 'video_provider' then case when not public.platform_feature_available('video_calls') then 'not_required' else r.manual_status end
        else r.manual_status
      end as derived_status,
      case r.requirement_key
        when 'assessment_translation_certification' then jsonb_build_object('certified',v_translated_certified,'required',32)
        when 'real_employer_supply' then jsonb_build_object('current',v_real_employers,'required',3)
        when 'real_opportunity_supply' then jsonb_build_object('current',v_real_opps,'required',10)
        when 'real_freelance_supply' then jsonb_build_object('current',v_real_tasks,'required',5)
        when 'real_scholarship_supply' then jsonb_build_object('current',v_real_scholarships,'required',5)
        when 'rls_all_public' then jsonb_build_object('public_tables',v_public_tables,'rls_enabled',v_rls_tables)
        when 'no_public_security_definers' then jsonb_build_object('exposed_count',v_public_definers)
        else '{}'::jsonb
      end as metrics
    from public.platform_launch_requirements r
  ), counts as (
    select count(*) filter(where required)::int required_count,
           count(*) filter(where required and derived_status in ('complete','not_required'))::int satisfied_count
    from derived
  )
  select jsonb_agg(jsonb_build_object(
      'requirement_key',requirement_key,'category',category,'title',title,'requirement_type',requirement_type,'required',required,
      'status',derived_status,'evidence_note',evidence_note,'evidence_url',evidence_url,'completed_by',completed_by,'completed_at',completed_at,'metrics',metrics
    ) order by category,title),
    (select required_count from counts),(select satisfied_count from counts)
  into v_items,v_required,v_satisfied
  from derived;

  return jsonb_build_object(
    'decision',case when v_required=v_satisfied then 'GO' else 'NO_GO' end,
    'required',v_required,'satisfied',v_satisfied,'remaining',v_required-v_satisfied,
    'items',coalesce(v_items,'[]'::jsonb),'computed_at',now()
  );
end $$;

create or replace function private.admin_update_platform_launch_requirement(p_requirement_key text,p_status text,p_evidence_note text default null,p_evidence_url text default null)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_type text; begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_status not in ('pending','complete','blocked','not_required') then raise exception 'invalid launch requirement status'; end if;
  select requirement_type into v_type from public.platform_launch_requirements where requirement_key=p_requirement_key;
  if not found then raise exception 'launch requirement not found'; end if;
  if v_type='auto' then raise exception 'automatic launch requirements cannot be manually overridden'; end if;
  update public.platform_launch_requirements set manual_status=p_status,evidence_note=nullif(trim(coalesce(p_evidence_note,'')),''),evidence_url=nullif(trim(coalesce(p_evidence_url,'')),''),completed_by=case when p_status='complete' then v_uid else null end,completed_at=case when p_status='complete' then now() else null end,updated_at=now() where requirement_key=p_requirement_key;
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'update_launch_requirement','platform_launch_requirement',null,jsonb_build_object('requirement_key',p_requirement_key,'status',p_status,'evidence_note',p_evidence_note,'evidence_url',p_evidence_url));
end $$;

create or replace function public.get_platform_launch_readiness()
returns jsonb language sql set search_path='' as $$ select private.get_platform_launch_readiness(); $$;
create or replace function public.admin_update_platform_launch_requirement(p_requirement_key text,p_status text,p_evidence_note text default null,p_evidence_url text default null)
returns void language sql set search_path='' as $$ select private.admin_update_platform_launch_requirement(p_requirement_key,p_status,p_evidence_note,p_evidence_url); $$;

revoke execute on function private.get_platform_launch_readiness() from public,anon;
revoke execute on function private.admin_update_platform_launch_requirement(text,text,text,text) from public,anon;
grant execute on function private.get_platform_launch_readiness() to authenticated,service_role;
grant execute on function private.admin_update_platform_launch_requirement(text,text,text,text) to authenticated,service_role;
revoke execute on function public.get_platform_launch_readiness() from public,anon;
revoke execute on function public.admin_update_platform_launch_requirement(text,text,text,text) from public,anon;
grant execute on function public.get_platform_launch_readiness() to authenticated;
grant execute on function public.admin_update_platform_launch_requirement(text,text,text,text) to authenticated;
;
