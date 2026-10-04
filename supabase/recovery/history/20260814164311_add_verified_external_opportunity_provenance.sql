-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814164311
alter table public.opportunities add column if not exists source_type text not null default 'employer';
alter table public.opportunities add column if not exists source_url text;
alter table public.opportunities add column if not exists source_verified_at timestamptz;
alter table public.opportunities add column if not exists source_verified_by uuid references public.profiles(id) on delete set null;
alter table public.opportunities add column if not exists source_notes text;
alter table public.opportunities add column if not exists source_last_checked_at timestamptz;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='opportunities_source_type_check' and conrelid='public.opportunities'::regclass) then
    alter table public.opportunities add constraint opportunities_source_type_check check (source_type in ('employer','official_external','platform_curated'));
  end if;
end $$;

create index if not exists opportunities_source_verified_by_idx on public.opportunities(source_verified_by);
create index if not exists opportunities_external_freshness_idx on public.opportunities(source_type,source_verified_at) where employer_id is null;

update public.opportunities set source_type='employer' where employer_id is not null and source_type is distinct from 'employer';

create or replace function private.prepare_opportunity()
returns trigger
language plpgsql
set search_path to ''
as $$
declare
  v_company public.employers%rowtype;
  v_platform_admin boolean:=false;
  v_source_fresh boolean:=false;
begin
  new.updated_at:=now();
  if new.posted_by is null then new.posted_by:=(select auth.uid()); end if;

  if new.employer_id is not null then
    select * into v_company from public.employers where id=new.employer_id;
    if not found then raise exception 'employer not found'; end if;
    new.organization_name:=v_company.company_name;
    new.organization:=v_company.company_name;
    if new.logo_url is null then new.logo_url:=v_company.logo_url; end if;
    if new.sector_category is null then new.sector_category:=v_company.sector_category; end if;
    new.source_type:='employer';
    new.verified_active:=(new.status='open' and new.deadline>=current_date and v_company.verified=true and v_company.verification_status='verified');
  else
    select exists(select 1 from public.profiles p where p.id=new.posted_by and p.role='admin'::public.user_role) into v_platform_admin;
    v_source_fresh:=(new.source_url is not null and new.source_url ~ '^https://' and new.source_verified_at is not null and new.source_verified_at>=now()-interval '30 days');
    if new.source_type='official_external' and new.external_url is null then new.external_url:=new.source_url; end if;
    if new.source_type='official_external' then new.application_method:='external'; end if;
    new.verified_active:=(v_platform_admin and new.source_type in ('official_external','platform_curated') and v_source_fresh and new.status='open' and new.deadline>=current_date);
  end if;

  if new.status='open' and (tg_op='INSERT' or old.status is distinct from 'open') then new.published_at:=coalesce(new.published_at,now()); end if;
  return new;
end $$;

create or replace function private.admin_upsert_external_opportunity(
  p_id uuid,
  p_title text,
  p_description text,
  p_organization_name text,
  p_location text,
  p_deadline date,
  p_sector_category public.launch_category,
  p_opportunity_type public.opportunity_type,
  p_employment_type_label text,
  p_source_url text,
  p_source_type text default 'official_external',
  p_summary text default null,
  p_stipend_or_reward text default 'See official source',
  p_requirements text[] default '{}',
  p_skills_required text[] default '{}',
  p_work_arrangement text default 'onsite',
  p_source_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid:=coalesce(p_id,gen_random_uuid()); begin
  if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
  if p_source_type not in ('official_external','platform_curated') then raise exception 'external source type required'; end if;
  if p_source_url is null or p_source_url !~ '^https://' then raise exception 'HTTPS official source URL required'; end if;
  if p_deadline<current_date then raise exception 'opportunity deadline is already past'; end if;
  insert into public.opportunities(
    id,posted_by,title,description,organization,location,external_url,deadline,status,employer_id,organization_name,sector_category,opportunity_type,employment_type_label,stipend_or_reward,requirements,skills_required,summary,work_arrangement,application_method,verified_source,source_type,source_url,source_verified_at,source_verified_by,source_notes,source_last_checked_at
  ) values(
    v_id,v_uid,trim(p_title),p_description,trim(p_organization_name),p_location,p_source_url,p_deadline,'open',null,trim(p_organization_name),p_sector_category,p_opportunity_type,p_employment_type_label,coalesce(p_stipend_or_reward,'See official source'),coalesce(p_requirements,'{}'),coalesce(p_skills_required,'{}'),p_summary,coalesce(p_work_arrangement,'onsite'),'external',p_source_url,p_source_type,p_source_url,now(),v_uid,nullif(trim(coalesce(p_source_notes,'')),''),now()
  )
  on conflict(id) do update set
    title=excluded.title,description=excluded.description,organization=excluded.organization,location=excluded.location,external_url=excluded.external_url,deadline=excluded.deadline,status='open',organization_name=excluded.organization_name,sector_category=excluded.sector_category,opportunity_type=excluded.opportunity_type,employment_type_label=excluded.employment_type_label,stipend_or_reward=excluded.stipend_or_reward,requirements=excluded.requirements,skills_required=excluded.skills_required,summary=excluded.summary,work_arrangement=excluded.work_arrangement,application_method='external',verified_source=excluded.verified_source,source_type=excluded.source_type,source_url=excluded.source_url,source_verified_at=now(),source_verified_by=v_uid,source_notes=excluded.source_notes,source_last_checked_at=now(),updated_at=now();
  insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'verify_external_opportunity','opportunity',v_id,jsonb_build_object('source_url',p_source_url,'source_type',p_source_type,'deadline',p_deadline));
  return v_id;
end $$;

create or replace function private.deactivate_stale_external_opportunities()
returns integer
language plpgsql
security definer
set search_path=''
as $$
declare v_count int; begin
  update public.opportunities
     set verified_active=false,updated_at=now()
   where employer_id is null and source_type in ('official_external','platform_curated') and verified_active=true
     and (source_verified_at is null or source_verified_at<now()-interval '30 days' or deadline<current_date);
  get diagnostics v_count=row_count;
  return v_count;
end $$;

create or replace function public.admin_upsert_external_opportunity(
  p_id uuid,p_title text,p_description text,p_organization_name text,p_location text,p_deadline date,p_sector_category public.launch_category,p_opportunity_type public.opportunity_type,p_employment_type_label text,p_source_url text,p_source_type text default 'official_external',p_summary text default null,p_stipend_or_reward text default 'See official source',p_requirements text[] default '{}',p_skills_required text[] default '{}',p_work_arrangement text default 'onsite',p_source_notes text default null
) returns uuid language sql set search_path='' as $$ select private.admin_upsert_external_opportunity(p_id,p_title,p_description,p_organization_name,p_location,p_deadline,p_sector_category,p_opportunity_type,p_employment_type_label,p_source_url,p_source_type,p_summary,p_stipend_or_reward,p_requirements,p_skills_required,p_work_arrangement,p_source_notes); $$;

revoke execute on function private.admin_upsert_external_opportunity(uuid,text,text,text,text,date,public.launch_category,public.opportunity_type,text,text,text,text,text,text[],text[],text,text) from public,anon;
revoke execute on function private.deactivate_stale_external_opportunities() from public,anon,authenticated;
grant execute on function private.admin_upsert_external_opportunity(uuid,text,text,text,text,date,public.launch_category,public.opportunity_type,text,text,text,text,text,text[],text[],text,text) to authenticated,service_role;
grant execute on function private.deactivate_stale_external_opportunities() to service_role;
revoke execute on function public.admin_upsert_external_opportunity(uuid,text,text,text,text,date,public.launch_category,public.opportunity_type,text,text,text,text,text,text[],text[],text,text) from public,anon;
grant execute on function public.admin_upsert_external_opportunity(uuid,text,text,text,text,date,public.launch_category,public.opportunity_type,text,text,text,text,text,text[],text[],text,text) to authenticated;

do $$
declare v_jobid bigint; begin
  select jobid into v_jobid from cron.job where jobname='mela-external-source-freshness';
  if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
  perform cron.schedule('mela-external-source-freshness','17 2 * * *','select private.deactivate_stale_external_opportunities();');
end $$;
;
