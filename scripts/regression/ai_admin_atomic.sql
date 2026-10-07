begin;
do $$
declare actor uuid; requester uuid; tid uuid:=gen_random_uuid(); aid uuid:=gen_random_uuid(); ag uuid; result jsonb; blocked boolean; prior boolean;
begin
 select au.user_id into actor from admin.admin_users au join admin.roles r on r.id=au.role_id where au.active and au.mfa_required and r.key='super_admin' limit 1;
 requester:=gen_random_uuid();
 insert into auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at) values(requester,requester::text||'@example.invalid','{"provider":"email"}','{"full_name":"AI rollback fixture","role":"student"}',now(),now(),now());
 select id,enabled into ag,prior from public.mela_ai_agents limit 1;
 if actor is null or requester is null or ag is null then raise exception 'Missing regression subjects'; end if;
 if has_function_privilege('authenticated','public.mela_ai_admin_mutate(uuid,text,uuid,text,boolean,text,text)','execute') then raise exception 'Browser mutation access'; end if;
 insert into public.mela_ai_tasks(id,created_by,title,status,approval_status,approval_level) values(tid,requester,'rollback fixture','waiting_approval','pending',2);
 insert into public.mela_ai_approvals(id,task_id,requested_by,level,action_type) values(aid,tid,requester,2,'regression');
 result:=public.mela_ai_admin_mutate(actor,'approval.review',aid,'regression-atomic',null,'approved','Regression');
 if result->'data'->>'status'<>'approved' or result->'task'->>'status'<>'queued' then raise exception 'Invalid transition'; end if;
 if not exists(select 1 from admin.audit_log where target_id=aid::text and request_id='regression-atomic') then raise exception 'Missing audit'; end if;
 blocked:=false;
 begin perform public.mela_ai_admin_mutate(actor,'approval.review',aid,'repeat',null,'rejected',null); exception when serialization_failure then blocked:=true; end;
 if not blocked then raise exception 'Review replay accepted'; end if;
 blocked:=false;
 begin perform public.mela_ai_admin_mutate(requester,'agent.toggle',ag,'unauthorized',not prior); exception when insufficient_privilege then blocked:=true; end;
 if not blocked then raise exception 'Non-admin mutation accepted'; end if;
 update public.mela_ai_approvals set status='pending',requested_by=actor where id=aid;
 update public.mela_ai_tasks set status='waiting_approval',approval_status='pending' where id=tid;
 blocked:=false;
 begin perform public.mela_ai_admin_mutate(actor,'approval.review',aid,'self',null,'approved',null); exception when insufficient_privilege then blocked:=true; end;
 if not blocked then raise exception 'Self approval accepted'; end if;
 update public.mela_ai_approvals set requested_by=requester where id=aid;
 update public.mela_ai_tasks set status='completed' where id=tid;
 blocked:=false;
 begin perform public.mela_ai_admin_mutate(actor,'approval.review',aid,'terminal',null,'approved',null); exception when serialization_failure then blocked:=true; end;
 if not blocked or (select status from public.mela_ai_approvals where id=aid)<>'pending' then raise exception 'Terminal task or approval changed'; end if;
 perform public.mela_ai_admin_mutate(actor,'agent.toggle',ag,'toggle',not prior);
 if (select enabled from public.mela_ai_agents where id=ag)=prior then raise exception 'Toggle failed'; end if;
end $$;
-- Failure injection is rolled back with the entire test transaction.
create function pg_temp.fail_ai_audit() returns trigger language plpgsql as $$begin raise exception 'simulated audit outage'; end$$;
create trigger regression_fail_ai_audit before insert on admin.audit_log for each row execute function pg_temp.fail_ai_audit();
do $$
declare actor uuid; ag uuid; prior boolean; blocked boolean:=false;
begin
 select au.user_id into actor from admin.admin_users au join admin.roles r on r.id=au.role_id where au.active and au.mfa_required and r.key='super_admin' limit 1;
 select id,enabled into ag,prior from public.mela_ai_agents limit 1;
 begin perform public.mela_ai_admin_mutate(actor,'agent.toggle',ag,'audit-failure',not prior); exception when raise_exception then blocked:=true; end;
 if not blocked or (select enabled from public.mela_ai_agents where id=ag) is distinct from prior then raise exception 'Mutation survived failed audit'; end if;
end $$;
rollback;
