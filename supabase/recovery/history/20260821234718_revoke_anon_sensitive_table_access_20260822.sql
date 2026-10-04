-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260821234718
revoke all on table public.coin_transactions, public.exam_results, public.external_application_tracking, public.learner_accessibility_preferences, public.learner_offline_sync_state, public.mela_learning_payment_attempts, public.mela_transition_plans, public.mela_transition_steps, public.opportunity_graph_edges, public.opportunity_graph_nodes, public.parent_link_invites, public.profile_documents, public.profile_education, public.profile_experience, public.profile_languages, public.profile_projects, public.user_subscriptions from anon;
;
