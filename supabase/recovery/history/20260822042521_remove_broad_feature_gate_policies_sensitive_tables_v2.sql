-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822042521
DROP POLICY IF EXISTS mela_gate_platform_live ON public."Mela";
DROP POLICY IF EXISTS mela_gate_assessments ON public.exam_results;
DROP POLICY IF EXISTS mela_gate_platform_live ON public.exam_results;
DROP POLICY IF EXISTS mela_gate_earn_work ON public.freelance_contracts;
DROP POLICY IF EXISTS mela_gate_platform_live ON public.freelance_contracts;
DROP POLICY IF EXISTS mela_gate_opportunities ON public.interview_candidate_responses;
DROP POLICY IF EXISTS mela_gate_platform_live ON public.interview_candidate_responses;
DROP POLICY IF EXISTS mela_gate_opportunities ON public.interviews;
DROP POLICY IF EXISTS mela_gate_platform_live ON public.interviews;
DROP POLICY IF EXISTS mela_master_gate ON public.learning_competencies;
DROP POLICY IF EXISTS mela_gate_academy ON public.skill_academy_certificates;
DROP POLICY IF EXISTS mela_gate_platform_live ON public.skill_academy_certificates;
;
