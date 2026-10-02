begin;
select set_config('request.jwt.claims','{"role":"authenticated"}',true);
do $test$
declare
  free_key text;
  paid_key text;
  material jsonb;
begin
  select material_key into free_key from public.mela_learning_materials where status='published' and access_tier='free' limit 1;
  select material_key into paid_key from public.mela_learning_materials where status='published' and access_tier<>'free' limit 1;
  if free_key is null or paid_key is null then raise exception 'published material fixtures missing'; end if;
  execute 'set local role authenticated';
  material:=public.get_mela_learning_material(free_key);
  if (material->>'locked')::boolean then raise exception 'free material was locked'; end if;
  material:=public.get_mela_learning_material(paid_key);
  if not (material->>'locked')::boolean or material ? 'content_markdown' then raise exception 'paid content exposed without entitlement'; end if;
end $test$;
rollback;
select 'PASS: free material access and paid-content lock without entitlement' as regression_result;
