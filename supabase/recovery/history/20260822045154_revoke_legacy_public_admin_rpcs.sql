-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822045154
revoke execute on function public.admin_education_value_readiness() from anon; revoke execute on function public.admin_education_value_readiness_v3() from anon; revoke execute on function public.get_mela_benchmark_blueprint_v2() from anon;
;
