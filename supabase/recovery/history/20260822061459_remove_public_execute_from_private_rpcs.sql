-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260822061459
revoke execute on function public.get_my_audience_context() from public; revoke execute on function public.get_my_policy_status() from public; revoke execute on function public.my_audience_feature_access(text) from public;
;
