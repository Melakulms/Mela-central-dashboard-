-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260923101010

-- Systemic version of the has_employer_access bug: 17 more private-schema
-- access-control helper functions are referenced directly inside RLS policy
-- expressions (found by searching pg_policies.qual/with_check text), but none
-- had EXECUTE granted to `authenticated`. Since RLS policies evaluate as the
-- querying role itself (not the definer of any function that happens to wrap
-- them), any policy using one of these would fail for every real user with
-- "permission denied for function X" -- covering arena teams/matches, employer
-- storage/contracts, video rooms, classrooms, guardian links, candidate
-- documents, challenges, and sector partner membership.
--
-- This grant does not change what these functions ALLOW -- each is still
-- SECURITY DEFINER with its real authorization logic fully intact internally
-- (ownership checks, membership checks, etc.). It only lets `authenticated`
-- invoke them at all, which is required for the RLS policies that already
-- depend on them to function for anyone.

GRANT EXECUTE ON FUNCTION private.application_update_actor(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_access_contract_storage(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_access_employer_storage(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_access_video_room(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_educate_learner(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_arena_tournament_team(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_arena_match(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_read_candidate_document(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_classroom(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_account_can_access() TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_challenge_manage_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_sector_partner_membership(uuid, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION private.has_verified_guardian_link(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_arena_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_arena_tournament_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_challenge_team_member(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_employer_owner_or_admin(uuid) TO authenticated;

;
