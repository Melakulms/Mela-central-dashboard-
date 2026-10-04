-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260903151932
create or replace function public.mela_ai_audit(p_actor uuid,p_action text,p_entity_type text,p_entity_id uuid,p_details jsonb default '{}'::jsonb) returns void language plpgsql security definer set search_path=public as $$ begin insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(p_actor,p_action,p_entity_type,p_entity_id,p_details); end; $$;
;
