-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260816062902
create or replace function private.protect_opportunity_moderation_v35()
returns trigger language plpgsql set search_path='pg_catalog','public','private' as $$
declare v_uid uuid:=(select auth.uid()); v_admin boolean:=false; v_server boolean:=current_user in ('postgres','service_role');
begin
 if v_server then return new; end if;
 if v_uid is null then raise exception 'authentication required'; end if;
 v_admin:=private.is_admin_user();
 if v_admin then return new; end if;
 if not exists(select 1 from public.profiles p where p.id=v_uid and p.role in ('company'::public.user_role,'employer'::public.user_role) and p.account_status='active' and (p.email_verified or p.phone_verified)) then
   raise exception 'verified company account required';
 end if;
 if tg_op='INSERT' then
   new.posted_by:=v_uid;
   new.moderation_status:='pending_review';
   new.reviewed_by:=null; new.reviewed_at:=null; new.moderation_notes:=null;
   new.verified_active:=false;
 elsif tg_op='UPDATE' then
   if new.moderation_status is distinct from old.moderation_status or new.reviewed_by is distinct from old.reviewed_by or new.reviewed_at is distinct from old.reviewed_at then
     raise exception 'vacancy moderation fields are admin managed';
   end if;
   if old.moderation_status='approved' and row(new.title,new.description,new.location,new.deadline,new.requirements,new.skills_required,new.salary_min,new.salary_max,new.external_url,new.application_instructions)
      is distinct from row(old.title,old.description,old.location,old.deadline,old.requirements,old.skills_required,old.salary_min,old.salary_max,old.external_url,old.application_instructions) then
     new.moderation_status:='pending_review'; new.verified_active:=false; new.published_at:=null;
   end if;
 end if;
 return new;
end $$;
drop trigger if exists trg_protect_opportunity_moderation_v35 on public.opportunities;
create trigger trg_protect_opportunity_moderation_v35 before insert or update on public.opportunities for each row execute function private.protect_opportunity_moderation_v35();

drop policy if exists "Opportunities readable" on public.opportunities;
create policy "Opportunities readable" on public.opportunities for select to anon,authenticated using (
 ((status='open' and verified_active=true and moderation_status='approved' and deadline>=current_date))
 or exists(select 1 from public.employers e where e.id=opportunities.employer_id and e.owner_id=(select auth.uid()))
 or exists(select 1 from public.employer_members m where m.employer_id=opportunities.employer_id and m.user_id=(select auth.uid()) and m.status='active')
 or private.is_admin_user()
);

create or replace function private.review_opportunity_v35(p_opportunity_id uuid,p_decision text,p_notes text default null)
returns public.opportunities language plpgsql security definer set search_path='' as $$
declare v_uid uuid:=(select auth.uid()); v_row public.opportunities%rowtype; v_status text;
begin
 if v_uid is null or not private.is_admin_user() then raise exception 'admin authorization required'; end if;
 if p_decision not in ('approved','rejected','suspended','archived') then raise exception 'invalid review decision'; end if;
 v_status:=case when p_decision='approved' then 'open' when p_decision in ('rejected','suspended','archived') then 'closed' else 'closed' end;
 update public.opportunities set moderation_status=p_decision,moderation_notes=nullif(trim(coalesce(p_notes,'')),''),reviewed_by=v_uid,reviewed_at=now(),verified_active=(p_decision='approved'),status=v_status,published_at=case when p_decision='approved' then coalesce(published_at,now()) else null end,updated_at=now()
 where id=p_opportunity_id returning * into v_row;
 if not found then raise exception 'opportunity not found'; end if;
 if v_row.posted_by is not null then
   insert into public.notifications(user_id,title,body,ref_table,ref_id) values(v_row.posted_by,case when p_decision='approved' then 'Vacancy approved' else 'Vacancy review updated' end,case when p_decision='approved' then 'Your vacancy is approved and can be published when platform launch gates allow it.' else 'Your vacancy status is now '||p_decision||'.' end,'opportunities',v_row.id);
 end if;
 insert into public.admin_audit_logs(actor_id,action,entity_type,entity_id,details) values(v_uid,'review_opportunity','opportunity',v_row.id,jsonb_build_object('decision',p_decision,'notes',p_notes));
 return v_row;
end $$;
create or replace function public.review_opportunity_v35(p_opportunity_id uuid,p_decision text,p_notes text default null)
returns public.opportunities language sql security invoker set search_path='' as $$ select * from private.review_opportunity_v35(p_opportunity_id,p_decision,p_notes); $$;
revoke all on function private.review_opportunity_v35(uuid,text,text) from public,anon,authenticated;
revoke all on function public.review_opportunity_v35(uuid,text,text) from public,anon;
grant execute on function public.review_opportunity_v35(uuid,text,text) to authenticated;
;
