# Database security review — 2 October 2026

This is a callable-function inventory and targeted review, not certification that every function is safe. All 109 browser-callable public SECURITY DEFINER entries delegate into private helpers. The warning count cannot be resolved safely by blanket revocation: existing authenticated feature RPCs depend on those helpers.

## Verified findings

- Ordinary learner self-promotion is denied by the repaired administrator/profile boundary (existing transactional regression).
- The Arena creator could finalize a match after round one timed out. Reproduced before repair; the same regression now rejects early completion while preserving the existing creator/admin boundary.
- `private.prepare_marketplace_task` and `private.protect_employer_member_identity_fields` evaluated `current_user` while running as SECURITY DEFINER. They now run as SECURITY INVOKER, so direct clients retain their own role and authorized SECURITY DEFINER RPCs retain their server role. Transactional regression verifies employer posting/editing, denial of forged assignment/completion, and a successful authorized task award.
- Authenticated roles have SELECT access, but no direct table-level financial mutation grants, on contracts, milestones, escrow and payout requests. Financial changes use guarded RPCs/service operations.
- Contract dispute retries now return the held contract without duplicating reports. Participant access, outsider denial and escrow hold pass transactional verification.
- Admin dispute listing requires active admin membership, MFA where required, and `support.manage`; unit tests reject dashboard-only access before reading dispute tables.

## Remaining review boundaries

The inventory below does not replace negative authorization tests for every delegated helper, including educator, video, pilot, review and tournament workflows. Nine no-policy tables remain private/service-only. Leaked-password protection remains disabled and requires Auth configuration access unavailable in the current connector.

Auth logs in the inspected available window contain a successful settings read, but no password sign-in request. This does not prove the user's credentials or browser network work.

## Public RPC inventory

| Function | Delegated helpers | Verification |
|---|---|---|
| `activate_my_educator_profile` | `activate_my_educator_profile` | Requires individual negative-case testing |
| `add_education_pilot_cohort` | `is_admin_user`, `has_sector_partner_membership` | Requires individual negative-case testing |
| `assign_arena_judge` | `assign_arena_judge` | Requires individual negative-case testing |
| `award_freelance_task` | `award_freelance_task` | Targeted transactional test |
| `can_review_questions_v18` | `can_review_questions_v18` | Requires individual negative-case testing |
| `cancel_arena_matchmaking` | `cancel_arena_matchmaking` | Requires individual negative-case testing |
| `cancel_freelance_contract` | `cancel_freelance_contract` | Requires individual negative-case testing |
| `cancel_mentorship_request` | `cancel_mentorship_request` | Requires individual negative-case testing |
| `cancel_mentorship_session` | `cancel_mentorship_session` | Requires individual negative-case testing |
| `check_scholarship_eligibility` | `current_user_is_premium`, `is_admin_user` | Requires individual negative-case testing |
| `complete_mentorship_session` | `complete_mentorship_session` | Requires individual negative-case testing |
| `complete_my_profile_v37` | `complete_my_profile_v37_impl` | Requires individual negative-case testing |
| `complete_practice_session` | `complete_practice_session` | Requires individual negative-case testing |
| `create_arena` | `create_arena` | Requires individual negative-case testing |
| `create_arena_season` | `create_arena_season` | Requires individual negative-case testing |
| `create_arena_team` | `create_arena_team` | Requires individual negative-case testing |
| `create_arena_tournament` | `create_arena_tournament` | Requires individual negative-case testing |
| `create_arena_tournament_team` | `create_arena_tournament_team` | Requires individual negative-case testing |
| `create_challenge_team` | `create_challenge_team` | Requires individual negative-case testing |
| `create_direct_video_call` | `create_direct_video_call` | Requires individual negative-case testing |
| `create_education_pilot` | `is_admin_user`, `has_sector_partner_membership` | Requires individual negative-case testing |
| `create_external_application_v12` | `create_external_application_v12` | Requires individual negative-case testing |
| `create_my_classroom` | `create_my_classroom` | Requires individual negative-case testing |
| `create_parent_link_invite_v35` | `create_parent_link_invite_v35` | Requires individual negative-case testing |
| `create_sponsored_challenge` | `create_sponsored_challenge` | Requires individual negative-case testing |
| `create_task_milestone` | `create_task_milestone` | Requires individual negative-case testing |
| `end_video_call` | `end_video_call` | Requires individual negative-case testing |
| `enroll_career_path` | `enroll_career_path` | Requires individual negative-case testing |
| `ensure_video_call_room` | `ensure_video_call_room` | Requires individual negative-case testing |
| `finish_arena` | `finish_arena` | Targeted transactional test |
| `generate_my_catchup_plan` | `generate_my_catchup_plan` | Requires individual negative-case testing |
| `get_assessment_attempt_questions_localized` | `get_assessment_attempt_questions_localized` | Requires individual negative-case testing |
| `get_data_protection_compliance_pack` | `get_data_protection_compliance_pack` | Requires individual negative-case testing |
| `get_generated_question_candidates_v18` | `get_generated_question_candidates_v18` | Requires individual negative-case testing |
| `get_mela_education_value_status` | `is_admin_user` | Requires individual negative-case testing |
| `get_mela_learning_library` | `is_admin_user`, `is_admin_user` | Requires individual negative-case testing |
| `get_mela_learning_material` | `is_admin_user` | Requires individual negative-case testing |
| `get_my_arena_creator_analytics` | `get_my_arena_creator_analytics` | Requires individual negative-case testing |
| `get_my_arena_stats` | `get_my_arena_stats` | Requires individual negative-case testing |
| `get_my_assessment_language_review` | `get_my_assessment_language_review` | Requires individual negative-case testing |
| `get_my_classroom_detail` | `can_view_classroom` | Requires individual negative-case testing |
| `get_my_dashboard_v36` | `get_my_dashboard_v36` | Requires individual negative-case testing |
| `get_my_partner_education_impact` | `is_admin_user`, `has_sector_partner_membership`, `is_admin_user`, `has_sector_partner_membership`, `is_admin_user`, `has_sector_partner_membership` | Requires individual negative-case testing |
| `get_my_practice_dashboard` | `get_my_practice_dashboard` | Requires individual negative-case testing |
| `get_my_practice_recommendations` | `get_my_practice_recommendations` | Requires individual negative-case testing |
| `get_my_question_bank_overview` | `get_my_question_bank_overview` | Requires individual negative-case testing |
| `get_platform_launch_readiness` | `get_platform_launch_readiness` | Requires individual negative-case testing |
| `get_platform_operational_health` | `get_platform_operational_health` | Requires individual negative-case testing |
| `get_question_catalog_v18` | `get_question_catalog_v18` | Requires individual negative-case testing |
| `get_question_quality_progress_v21` | `get_question_quality_progress_v21` | Requires individual negative-case testing |
| `get_question_review_queue_v18` | `get_question_review_queue_v18` | Requires individual negative-case testing |
| `get_question_review_slice_v18` | `get_question_review_slice_v18` | Requires individual negative-case testing |
| `get_question_subject_detail_v18` | `get_question_subject_detail_v18` | Requires individual negative-case testing |
| `invite_arena_user` | `invite_arena_user` | Requires individual negative-case testing |
| `invite_video_call_participant` | `invite_video_call_participant` | Requires individual negative-case testing |
| `join_arena` | `join_arena` | Requires individual negative-case testing |
| `join_arena_matchmaking` | `join_arena_matchmaking` | Targeted transactional test |
| `join_arena_team` | `join_arena_team` | Requires individual negative-case testing |
| `join_arena_tournament_team` | `join_arena_tournament_team` | Requires individual negative-case testing |
| `join_challenge_team` | `join_challenge_team` | Requires individual negative-case testing |
| `join_educator_classroom` | `join_educator_classroom` | Requires individual negative-case testing |
| `join_sponsored_challenge` | `join_sponsored_challenge` | Requires individual negative-case testing |
| `join_video_call` | `join_video_call` | Requires individual negative-case testing |
| `leave_video_call` | `leave_video_call` | Requires individual negative-case testing |
| `open_arena_tournament_registration` | `open_arena_tournament_registration` | Requires individual negative-case testing |
| `raise_contract_dispute` | `raise_contract_dispute` | Targeted transactional test |
| `record_arena_integrity_event` | `record_arena_integrity_event` | Requires individual negative-case testing |
| `record_education_pilot_measurement` | `is_admin_user`, `has_sector_partner_membership`, `is_admin_user` | Requires individual negative-case testing |
| `record_educator_observation` | `record_educator_observation` | Requires individual negative-case testing |
| `redeem_parent_link_invite_v35` | `redeem_parent_link_invite_v35` | Requires individual negative-case testing |
| `refresh_my_opportunity_matches` | `refresh_my_opportunity_matches` | Requires individual negative-case testing |
| `refresh_my_school_safety_status` | `user_has_adult_work_attestation` | Requires individual negative-case testing |
| `register_arena_tournament` | `register_arena_tournament` | Requires individual negative-case testing |
| `register_arena_tournament_team` | `register_arena_tournament_team` | Requires individual negative-case testing |
| `request_video_call_recording` | `request_video_call_recording` | Requires individual negative-case testing |
| `respond_arena_invite` | `respond_arena_invite` | Requires individual negative-case testing |
| `respond_freelance_contract` | `respond_freelance_contract` | Requires individual negative-case testing |
| `respond_mentorship_request` | `is_admin_user` | Requires individual negative-case testing |
| `respond_video_call_invite` | `respond_video_call_invite` | Requires individual negative-case testing |
| `respond_video_call_recording_consent` | `respond_video_call_recording_consent` | Requires individual negative-case testing |
| `review_task_milestone` | `review_task_milestone` | Requires individual negative-case testing |
| `run_my_evidence_diagnostic` | `run_my_evidence_diagnostic` | Requires individual negative-case testing |
| `save_my_accessibility_preferences_v12` | `save_my_accessibility_preferences_v12` | Requires individual negative-case testing |
| `schedule_mentorship_session` | `schedule_mentorship_session` | Requires individual negative-case testing |
| `select_account_type_v35` | `select_account_type_v35` | Requires individual negative-case testing |
| `set_arena_ready` | `set_arena_ready` | Requires individual negative-case testing |
| `set_education_pilot_metric` | `is_admin_user`, `has_sector_partner_membership` | Requires individual negative-case testing |
| `set_my_education_stage_v36` | `set_my_education_stage_v36` | Requires individual negative-case testing |
| `set_my_mela_next_goal` | `set_my_mela_next_goal` | Requires individual negative-case testing |
| `shortlist_freelance_proposal` | `shortlist_freelance_proposal` | Requires individual negative-case testing |
| `start_arena` | `start_arena` | Targeted transactional test |
| `start_arena_tournament` | `start_arena_tournament` | Requires individual negative-case testing |
| `start_mela_filtered_question_session_v15` | `start_mela_filtered_question_session_v18` | Requires individual negative-case testing |
| `start_mela_filtered_question_session_v18` | `start_mela_filtered_question_session_v18` | Requires individual negative-case testing |
| `start_mela_question_session` | `start_mela_question_session` | Requires individual negative-case testing |
| `start_mela_question_session_v12` | `start_mela_filtered_question_session_v18` | Requires individual negative-case testing |
| `start_practice_mock` | `start_practice_mock` | Requires individual negative-case testing |
| `start_practice_session` | `start_practice_session` | Requires individual negative-case testing |
| `start_video_call_recording` | `start_video_call_recording` | Requires individual negative-case testing |
| `submit_arena_round` | `submit_arena_round` | Targeted transactional test |
| `submit_challenge_entry` | `submit_challenge_entry` | Requires individual negative-case testing |
| `submit_mela_question_session` | `submit_mela_question_session` | Requires individual negative-case testing |
| `submit_mela_question_session_v12` | `submit_mela_question_session_v12` | Requires individual negative-case testing |
| `submit_practice_response` | `submit_practice_response` | Requires individual negative-case testing |
| `submit_task_milestone` | `submit_task_milestone` | Requires individual negative-case testing |
| `submit_task_milestone` | `submit_task_milestone` | Requires individual negative-case testing |
| `submit_work_review` | `submit_work_review` | Requires individual negative-case testing |
| `track_global_source_v16` | `track_global_source_v16` | Requires individual negative-case testing |
| `withdraw_freelance_proposal` | `withdraw_freelance_proposal` | Requires individual negative-case testing |

## Classroom response boundary repair

`get_my_classroom_detail` previously applied access checks only to the classroom object, leaving its learner aggregation unguarded. The full response now checks authenticated classroom access first. Teacher/member/outsider rollback regressions pass. This targeted fix does not certify the remaining functions.
