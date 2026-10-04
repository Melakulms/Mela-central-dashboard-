-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20261002053531
CREATE OR REPLACE FUNCTION private.process_employer_registration_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=false; v_employer_id uuid; v_server boolean:=private.is_admin_user();
begin
  v_admin:=private.is_admin_user();
  if tg_op='UPDATE' and not v_admin and not v_server then
    if new.status is distinct from old.status or new.review_notes is distinct from old.review_notes or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at or new.employer_id is distinct from old.employer_id then raise exception 'review fields are admin managed'; end if;
    if old.status not in ('pending','under_review') then raise exception 'request can no longer be edited'; end if;
  end if;
  new.updated_at:=now();
  if tg_op='UPDATE' and new.status in ('approved','rejected') and new.status is distinct from old.status then new.reviewed_by:=coalesce(v_uid,new.reviewed_by); new.reviewed_at:=now(); end if;
  if tg_op='UPDATE' and new.status='approved' and old.status is distinct from 'approved' then
    update public.profiles set role='employer'::public.user_role where id=new.applicant_user_id;
    if new.employer_id is null then
      insert into public.employers(owner_id,company_name,legal_name,registration_number,industry,sector_category,website,contact_email,phone_number,headquarters,description,verified,verification_status)
      values(new.applicant_user_id,new.company_name,new.legal_name,new.registration_number,new.industry,new.sector_category,new.website,new.contact_email,new.phone_number,new.headquarters,new.description,false,'pending')
      returning id into v_employer_id; new.employer_id:=v_employer_id;
    end if;
  end if;
  return new;
end;$function$
;
CREATE OR REPLACE FUNCTION private.prepare_opportunity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
    new.verified_active:=(new.moderation_status='approved' and new.moderation_status='approved' and new.status='open' and new.deadline>=current_date and v_company.verified=true and v_company.verification_status='verified');
  else
    select exists(select 1 from public.profiles p where p.id=new.posted_by and p.role='admin'::public.user_role) into v_platform_admin;
    v_source_fresh:=(new.source_url is not null and new.source_url ~ '^https://' and new.source_verified_at is not null and new.source_verified_at>=now()-interval '30 days');
    if new.source_type='official_external' and new.external_url is null then new.external_url:=new.source_url; end if;
    if new.source_type='official_external' then new.application_method:='external'; end if;
    new.verified_active:=(v_platform_admin and new.source_type in ('official_external','platform_curated') and v_source_fresh and new.status='open' and new.deadline>=current_date);
  end if;

  if new.status='open' and (tg_op='INSERT' or old.status is distinct from 'open') then new.published_at:=coalesce(new.published_at,now()); end if;
  return new;
end $function$
;

create or replace function public.enforce_employer_review_transition() returns trigger language plpgsql set search_path='' as $$
begin
 if new.status in ('approved','rejected') and nullif(trim(coalesce(new.review_notes,'')),'') is null then raise exception 'Review reason is required'; end if;
 if new.status is distinct from old.status and not (
 (old.status='pending' and new.status in ('under_review','approved','rejected','cancelled'))
 or (old.status='under_review' and new.status in ('pending','approved','rejected','cancelled'))
 ) then raise exception 'Invalid employer review transition: % -> %',old.status,new.status; end if;
 return new;
end; $$;
create or replace function public.enforce_opportunity_review_transition() returns trigger language plpgsql set search_path='' as $$
begin
 if new.moderation_status in ('approved','rejected') and nullif(trim(coalesce(new.moderation_notes,'')),'') is null then raise exception 'Moderation reason is required'; end if;
 if new.moderation_status is distinct from old.moderation_status and not (
 (old.moderation_status='pending_review' and new.moderation_status in ('approved','rejected','flagged'))
 or (old.moderation_status='flagged' and new.moderation_status in ('pending_review','approved','rejected','suspended'))
 or (old.moderation_status='rejected' and new.moderation_status='pending_review')
 or (old.moderation_status='approved' and new.moderation_status in ('pending_review','flagged','suspended','archived'))
 or (old.moderation_status='suspended' and new.moderation_status in ('pending_review','archived'))
 ) then raise exception 'Invalid opportunity review transition: % -> %',old.moderation_status,new.moderation_status; end if;
 -- Preparation later derives visibility from moderation, source verification and deadline.
 if new.moderation_status<>'approved' then new.verified_active:=false; end if;
 return new;
end; $$;
-- These two policies used a verification status that the employer constraint forbids.
do $$
declare p record;
begin
 for p in select polname,pg_get_expr(polqual,polrelid) q,pg_get_expr(polwithcheck,polrelid) c from pg_policy where polrelid='public.opportunities'::regclass and polname in ('Employer teams create opportunities','Employer teams update opportunities') loop
 execute format('alter policy %I on public.opportunities %s %s',p.polname,
 case when p.q is null then '' else 'using ('||replace(p.q,'''approved''::text','''verified''::text')||')' end,
 case when p.c is null then '' else 'with check ('||replace(p.c,'''approved''::text','''verified''::text')||')' end);
 end loop;
end; $$;

;
