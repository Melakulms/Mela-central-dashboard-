-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815104926
alter table public.global_opportunity_sources add column if not exists allowed_application_domains text[] not null default '{}'::text[];
update public.global_opportunity_sources set allowed_application_domains=array[canonical_domain] where cardinality(allowed_application_domains)=0;
update public.global_opportunity_sources set allowed_application_domains=array['ufhb.edu.ci','scolarite-ufhb.edu.ci'],updated_at=now() where country_code='CI' and source_name='Université Félix Houphouët-Boigny';
update public.global_opportunity_sources set allowed_application_domains=array['unan.edu.ni','setec.edu.ni'],updated_at=now() where country_code='NI' and source_name='UNAN-Managua';

create or replace function private.create_external_application_v12(p_source_id uuid,p_external_title text,p_institution_name text,p_application_type text,p_external_url text,p_external_reference text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_id uuid; v_src public.global_opportunity_sources%rowtype; v_host text; v_allowed boolean:=false; d text; begin
 if v_uid is null then raise exception 'authentication required'; end if;
 if nullif(trim(coalesce(p_external_title,'')),'') is null then raise exception 'title required'; end if;
 if p_application_type not in ('university','college','job','internship','scholarship','training','other') then raise exception 'invalid application type'; end if;
 if p_external_url !~* '^https://' then raise exception 'https external url required'; end if;
 v_host:=lower(substring(p_external_url from '^https?://([^/]+)'));
 if p_source_id is not null then
   select * into v_src from public.global_opportunity_sources where id=p_source_id and active and verification_status='verified';
   if not found then raise exception 'verified source required'; end if;
   foreach d in array v_src.allowed_application_domains loop
     if v_host=lower(d) or v_host like '%.'||lower(d) then v_allowed:=true; exit; end if;
   end loop;
   if not v_allowed then raise exception 'external url must match a verified application domain'; end if;
 end if;
 insert into public.external_application_tracking(user_id,source_id,external_title,institution_name,country_code,application_type,external_url,external_reference,status,notes)
 values(v_uid,p_source_id,trim(p_external_title),nullif(trim(coalesce(p_institution_name,'')),''),case when p_source_id is null then null else v_src.country_code end,p_application_type,p_external_url,nullif(trim(coalesce(p_external_reference,'')),''),'saved',nullif(trim(coalesce(p_notes,'')),'')) returning id into v_id;
 insert into public.external_application_events(application_id,user_id,event_type,new_status,note) values(v_id,v_uid,'created','saved','Application tracker created in Mela; external status is manual unless the source has a verified API integration.');
 return v_id;
end $$;
revoke all on function private.create_external_application_v12(uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function private.create_external_application_v12(uuid,text,text,text,text,text,text) to authenticated,service_role;
;
