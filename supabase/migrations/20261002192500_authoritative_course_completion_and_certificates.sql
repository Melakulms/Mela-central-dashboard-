create table if not exists public.course_certificates (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  certificate_code text not null unique,
  credential_type text not null,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz null,
  revoke_reason text null,
  metadata jsonb not null default '{}'::jsonb,
  unique(user_id,course_id),
  constraint course_certificate_code_not_blank check (btrim(certificate_code)<>''),
  constraint course_certificate_credential_not_blank check (btrim(credential_type)<>'')
);

alter table public.course_certificates enable row level security;
revoke all on public.course_certificates from public,anon,authenticated;
grant select on public.course_certificates to authenticated;

drop policy if exists course_certificates_read_self_or_admin on public.course_certificates;
create policy course_certificates_read_self_or_admin on public.course_certificates
for select to authenticated
using (user_id=(select auth.uid()) or private.is_admin_user());

create or replace function private.refresh_course_enrollment_from_lessons(p_user_id uuid,p_course_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_total integer:=0;
  v_done integer:=0;
  v_pct integer:=0;
  v_credential text;
  v_certificate_id uuid;
begin
  select count(*) into v_total from public.course_lessons where course_id=p_course_id;
  select count(*) into v_done
  from public.lesson_progress lp join public.course_lessons cl on cl.id=lp.lesson_id
  where lp.user_id=p_user_id and cl.course_id=p_course_id;
  v_pct:=case when v_total=0 then 0 else least(100,round(v_done*100.0/v_total)::integer) end;

  update public.course_enrollments
  set progress_pct=v_pct,completed_at=case when v_pct=100 then coalesce(completed_at,now()) else completed_at end
  where user_id=p_user_id and course_id=p_course_id;

  if v_total>0 and v_done=v_total then
    select nullif(btrim(credential_type),'') into v_credential from public.courses where id=p_course_id and is_published=true;
    if v_credential is not null then
      insert into public.course_certificates(user_id,course_id,certificate_code,credential_type,metadata)
      values(p_user_id,p_course_id,'MELA-C-'||upper(replace(gen_random_uuid()::text,'-','')),v_credential,
             jsonb_build_object('completion_source','course_lessons','completed_lessons',v_done,'total_lessons',v_total))
      on conflict(user_id,course_id) do nothing
      returning id into v_certificate_id;
      if v_certificate_id is not null then
        perform private.create_notification(p_user_id,'Course credential earned','You completed a MELA course and earned a verified credential.','course_certificates',v_certificate_id);
      end if;
    end if;
  end if;
end;
$function$;

create or replace function private.refresh_course_enrollment_after_lesson_progress()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare v_course_id uuid;
begin
  select course_id into v_course_id from public.course_lessons where id=new.lesson_id;
  if v_course_id is not null then perform private.refresh_course_enrollment_from_lessons(new.user_id,v_course_id); end if;
  return new;
end;
$function$;

drop trigger if exists trg_refresh_course_enrollment_after_lesson_progress on public.lesson_progress;
create trigger trg_refresh_course_enrollment_after_lesson_progress
after insert on public.lesson_progress
for each row execute function private.refresh_course_enrollment_after_lesson_progress();

drop policy if exists lesson_progress_self_delete on public.lesson_progress;
revoke delete on public.lesson_progress from authenticated;

create or replace function public.verify_course_certificate(p_certificate_code text)
returns table(certificate_code text,credential_type text,course_title text,learner_name text,issued_at timestamptz,valid boolean)
language sql
stable
security definer
set search_path to ''
as $function$
  select cc.certificate_code,cc.credential_type,c.title,p.full_name,cc.issued_at,(cc.revoked_at is null) as valid
  from public.course_certificates cc
  join public.courses c on c.id=cc.course_id
  join public.profiles p on p.id=cc.user_id
  where cc.certificate_code=upper(btrim(p_certificate_code));
$function$;

revoke all on function public.verify_course_certificate(text) from public;
grant execute on function public.verify_course_certificate(text) to anon,authenticated;

with totals as (
  select course_id,count(*)::integer as total_lessons from public.course_lessons group by course_id
), done as (
  select lp.user_id,cl.course_id,count(*)::integer as completed_lessons
  from public.lesson_progress lp join public.course_lessons cl on cl.id=lp.lesson_id
  group by lp.user_id,cl.course_id
), recalculated as (
  select ce.id,ce.user_id,ce.course_id,
         case when coalesce(t.total_lessons,0)=0 then 0 else least(100,round(coalesce(d.completed_lessons,0)*100.0/t.total_lessons)::integer) end as pct
  from public.course_enrollments ce
  left join totals t on t.course_id=ce.course_id
  left join done d on d.user_id=ce.user_id and d.course_id=ce.course_id
)
update public.course_enrollments ce
set progress_pct=r.pct,completed_at=case when r.pct=100 then coalesce(ce.completed_at,now()) else ce.completed_at end
from recalculated r
where ce.id=r.id and ce.progress_pct is distinct from r.pct;
