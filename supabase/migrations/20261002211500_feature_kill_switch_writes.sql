-- Production-applied: make disabled feature flags authoritative for marketplace/challenge writes.
-- Administrators may prepare content; users may still cancel/clean up existing records.

create or replace function private.enforce_feature_kill_switch_write()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_admin boolean := private.is_admin_user();
  v_available boolean;
begin
  if v_admin then return coalesce(new,old); end if;

  if tg_table_name in ('marketplace_tasks','marketplace_submissions') then
    v_available := public.platform_feature_available('earn_work');
    if not v_available then
      if tg_table_name='marketplace_tasks' then
        if tg_op='INSERT' or (tg_op='UPDATE' and new.status='open' and new.status is distinct from old.status) then
          raise exception 'Earn & Work is temporarily disabled';
        end if;
      else
        if tg_op='INSERT' or (tg_op='UPDATE' and new.status in ('shortlisted','accepted') and new.status is distinct from old.status) then
          raise exception 'Earn & Work is temporarily disabled';
        end if;
      end if;
    end if;
  elsif tg_table_name in ('sponsored_challenges','challenge_participants','challenge_submissions') then
    v_available := public.platform_feature_available('challenges');
    if not v_available then
      if tg_table_name='sponsored_challenges' then
        if tg_op='INSERT' or (tg_op='UPDATE' and new.status in ('published','open') and new.status is distinct from old.status) then
          raise exception 'Sponsored challenges are temporarily disabled';
        end if;
      elsif tg_table_name='challenge_participants' then
        if tg_op='INSERT' or (tg_op='UPDATE' and new.status='active' and new.status is distinct from old.status) then
          raise exception 'Sponsored challenges are temporarily disabled';
        end if;
      else
        if tg_op='INSERT' or (tg_op='UPDATE' and new.status='submitted') then
          raise exception 'Sponsored challenges are temporarily disabled';
        end if;
      end if;
    end if;
  end if;

  return coalesce(new,old);
end;
$function$;

drop trigger if exists trg_00_feature_kill_switch_marketplace_tasks on public.marketplace_tasks;
create trigger trg_00_feature_kill_switch_marketplace_tasks before insert or update on public.marketplace_tasks for each row execute function private.enforce_feature_kill_switch_write();
drop trigger if exists trg_00_feature_kill_switch_marketplace_submissions on public.marketplace_submissions;
create trigger trg_00_feature_kill_switch_marketplace_submissions before insert or update on public.marketplace_submissions for each row execute function private.enforce_feature_kill_switch_write();
drop trigger if exists trg_00_feature_kill_switch_sponsored_challenges on public.sponsored_challenges;
create trigger trg_00_feature_kill_switch_sponsored_challenges before insert or update on public.sponsored_challenges for each row execute function private.enforce_feature_kill_switch_write();
drop trigger if exists trg_00_feature_kill_switch_challenge_participants on public.challenge_participants;
create trigger trg_00_feature_kill_switch_challenge_participants before insert or update on public.challenge_participants for each row execute function private.enforce_feature_kill_switch_write();
drop trigger if exists trg_00_feature_kill_switch_challenge_submissions on public.challenge_submissions;
create trigger trg_00_feature_kill_switch_challenge_submissions before insert or update on public.challenge_submissions for each row execute function private.enforce_feature_kill_switch_write();
