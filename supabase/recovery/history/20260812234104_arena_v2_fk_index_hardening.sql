-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812234104
create index if not exists arena_integrity_events_user_idx on public.arena_integrity_events(user_id);
create index if not exists arena_integrity_summaries_reviewed_by_idx on public.arena_integrity_summaries(reviewed_by);
create index if not exists arena_judges_assigned_by_idx on public.arena_judges(assigned_by);
create index if not exists arena_matchmaking_assessment_idx on public.arena_matchmaking_queue(assessment_id);
create index if not exists arena_matchmaking_career_path_idx on public.arena_matchmaking_queue(career_path_id);
create index if not exists arena_matchmaking_matched_match_idx on public.arena_matchmaking_queue(matched_match_id);
create index if not exists arena_reward_rules_badge_idx on public.arena_reward_rules(badge_id);
create index if not exists arena_reward_rules_created_by_idx on public.arena_reward_rules(created_by);
create index if not exists arena_rewards_badge_idx on public.arena_rewards(badge_id);
create index if not exists arena_rewards_arena_team_idx on public.arena_rewards(beneficiary_arena_team_id);
create index if not exists arena_rewards_tournament_team_idx on public.arena_rewards(beneficiary_tournament_team_id);
create index if not exists arena_seasons_career_path_idx on public.arena_seasons(career_path_id);
create index if not exists arena_seasons_created_by_idx on public.arena_seasons(created_by);
create index if not exists arena_tournament_competitors_team_idx on public.arena_tournament_competitors(tournament_team_id);
create index if not exists arena_tournament_competitors_user_idx on public.arena_tournament_competitors(user_id);
create index if not exists arena_tournament_pairings_comp_a_idx on public.arena_tournament_pairings(competitor_a_id);
create index if not exists arena_tournament_pairings_comp_b_idx on public.arena_tournament_pairings(competitor_b_id);
create index if not exists arena_tournament_pairings_winner_idx on public.arena_tournament_pairings(winner_competitor_id);
create index if not exists arena_tournament_teams_captain_idx on public.arena_tournament_teams(captain_id);
create index if not exists arena_tournaments_assessment_idx on public.arena_tournaments(assessment_id);
create index if not exists arena_tournaments_career_path_idx on public.arena_tournaments(career_path_id);
create index if not exists arena_tournaments_created_by_idx on public.arena_tournaments(created_by);
create index if not exists career_passport_achievements_verified_by_idx on public.career_passport_achievements(verified_by);
;
