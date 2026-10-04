-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812222322
create or replace function private.finalize_sponsored_challenge(p_challenge_id uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_winner uuid;
  v_user uuid;
  v_team uuid;
  v_prize numeric;
  v_currency text;
  v_review record;
  v_member record;
begin
  if not private.has_challenge_manage_access(p_challenge_id) then raise exception 'challenge management access required'; end if;
  if not exists(select 1 from public.challenge_submissions where challenge_id=p_challenge_id and status in ('submitted','under_review','finalist')) then raise exception 'no eligible submissions'; end if;

  update public.sponsored_challenges set status='judging',updated_at=now() where id=p_challenge_id;

  for v_review in
    select s.id,coalesce(avg(cr.total_score),0)::numeric as avg_score,count(cr.id)::int as rc
    from public.challenge_submissions s
    left join public.challenge_reviews cr on cr.submission_id=s.id
    where s.challenge_id=p_challenge_id and s.status in ('submitted','under_review','finalist')
    group by s.id
  loop
    update public.challenge_submissions
      set final_score=v_review.avg_score,score=v_review.avg_score,review_count=v_review.rc,status='under_review',updated_at=now()
      where id=v_review.id;
  end loop;

  with ranked as (
    select id,row_number() over(order by final_score desc nulls last,submitted_at asc) rn
    from public.challenge_submissions
    where challenge_id=p_challenge_id and status='under_review'
  )
  update public.challenge_submissions s
     set rank=rk.rn,
         status=case when rk.rn=1 then 'winner' when rk.rn<=3 then 'finalist' else 'rejected' end,
         updated_at=now()
    from ranked rk
   where s.id=rk.id;

  select id,user_id,team_id into v_winner,v_user,v_team
  from public.challenge_submissions where challenge_id=p_challenge_id and rank=1;
  if v_winner is null then raise exception 'winner could not be determined'; end if;

  select prize_amount_etb,prize_currency into v_prize,v_currency
  from public.sponsored_challenges where id=p_challenge_id;

  update public.sponsored_challenges
     set status='completed',winner_submission_id=v_winner,updated_at=now()
   where id=p_challenge_id;

  insert into public.challenge_rewards(challenge_id,submission_id,beneficiary_user_id,beneficiary_team_id,amount,currency,status)
  values(p_challenge_id,v_winner,case when v_team is null then v_user else null end,v_team,coalesce(v_prize,0),coalesce(v_currency,'ETB'),'approved')
  on conflict(challenge_id,submission_id) do nothing;

  if v_team is null then
    perform private.create_notification(v_user,'Challenge winner','Congratulations — your sponsored challenge submission ranked first.','challenge_submissions',v_winner);
  else
    for v_member in select user_id from public.challenge_team_members where team_id=v_team loop
      perform private.create_notification(v_member.user_id,'Challenge winner','Congratulations — your team ranked first in a sponsored challenge.','challenge_submissions',v_winner);
    end loop;
  end if;
  return v_winner;
end $$;
;
