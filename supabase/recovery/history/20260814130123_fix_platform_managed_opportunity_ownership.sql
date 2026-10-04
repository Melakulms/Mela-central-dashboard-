-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814130123
create or replace function private.sync_opportunity_compat_fields()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_owner uuid;
begin
  -- posted_by is a profile/user id; employer_id is an employers.id. They are not interchangeable.
  -- For legacy employer-authored rows, derive the profile owner from the employer record instead.
  if new.posted_by is null and new.employer_id is not null then
    select e.owner_id into v_owner from public.employers e where e.id=new.employer_id;
    new.posted_by := v_owner;
  end if;
  if new.organization_name is null then new.organization_name := new.organization; end if;
  if new.organization is null then new.organization := new.organization_name; end if;
  return new;
end;
$function$;

create or replace function private.prepare_opportunity()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_company public.employers%rowtype;
  v_platform_admin boolean := false;
begin
  new.updated_at := now();
  if new.posted_by is null then new.posted_by := (select auth.uid()); end if;

  if new.employer_id is not null then
    select * into v_company from public.employers where id=new.employer_id;
    if not found then raise exception 'employer not found'; end if;
    new.organization_name := v_company.company_name;
    new.organization := v_company.company_name;
    if new.logo_url is null then new.logo_url := v_company.logo_url; end if;
    if new.sector_category is null then new.sector_category := v_company.sector_category; end if;
    new.verified_active := (
      new.status='open' and new.deadline >= current_date and
      v_company.verified = true and v_company.verification_status='verified'
    );
  else
    select exists(
      select 1 from public.profiles p
      where p.id=new.posted_by and p.role='admin'::public.user_role
    ) into v_platform_admin;
    -- Platform/admin-curated opportunities (notably scholarships) can be verified without inventing an employer row.
    new.verified_active := (
      v_platform_admin and new.status='open' and new.deadline >= current_date
    );
  end if;

  if new.status='open' and (tg_op='INSERT' or old.status is distinct from 'open') then
    new.published_at := coalesce(new.published_at, now());
  end if;
  return new;
end;
$function$;
;
