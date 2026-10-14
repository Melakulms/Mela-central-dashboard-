-- Synthetic accounts only. Every row created here is rolled back.
BEGIN;
DO $test$
DECLARE u uuid:=gen_random_uuid(); super_role uuid; denied boolean; n integer;
BEGIN
  INSERT INTO auth.users(id,email,raw_app_meta_data,raw_user_meta_data,email_confirmed_at,created_at,updated_at)
  VALUES(u,u::text||'@example.invalid','{"provider":"email"}','{"full_name":"Security regression fixture","role":"student"}',now(),now(),now());
  UPDATE public.profiles SET role='admin',account_status='active',email_verified=true,deleted_at=null WHERE id=u;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','aal','aal2')::text,true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  IF public.mela_is_admin() THEN RAISE EXCEPTION 'Profile-only admin bypass'; END IF;
  -- Exercise an actual policy without accessing any real user records.
  denied:=false;
  BEGIN
    INSERT INTO public.skill_assessments(title) VALUES('Security denied fixture');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Profile-only admin could write assessments'; END IF;
  denied:=false;
  BEGIN
    INSERT INTO public.skill_assessment_results(user_id,score,level) VALUES(u,100,'forged');
  EXCEPTION WHEN insufficient_privilege THEN denied:=true;
  END;
  IF NOT denied THEN RAISE EXCEPTION 'Client could forge an assessment result'; END IF;
  SELECT count(*) INTO n FROM public.profiles WHERE id=u;
  IF n<>1 THEN RAISE EXCEPTION 'Own-profile read regressed'; END IF;
  EXECUTE 'RESET ROLE';
  SELECT id INTO super_role FROM admin.roles WHERE key='super_admin';
  INSERT INTO admin.admin_users(user_id,role_id,active,mfa_required) VALUES(u,super_role,true,true);
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','aal','aal1')::text,true);
  IF public.mela_is_admin() THEN RAISE EXCEPTION 'AAL1 administrator bypass'; END IF;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','aal','aal2')::text,true);
  IF NOT public.mela_is_admin() THEN RAISE EXCEPTION 'Verified central super-admin denied'; END IF;
  -- Clear test claims before server-side fixture maintenance.
  PERFORM set_config('request.jwt.claims','{}',true);
  UPDATE public.profiles SET account_status='suspended' WHERE id=u;
  PERFORM set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','aal','aal2')::text,true);
  IF public.mela_is_admin() OR private.current_account_can_access() THEN RAISE EXCEPTION 'Suspended account retained access'; END IF;
  PERFORM set_config('request.jwt.claims','{}',true);
  IF EXISTS(SELECT 1 FROM pg_policies WHERE schemaname='public' AND (qual LIKE '%p.role = ''admin''%' OR with_check LIKE '%p.role = ''admin''%')) THEN
    RAISE EXCEPTION 'Legacy policy admin predicate remains';
  END IF;
  IF has_function_privilege('authenticated','private.refresh_course_enrollment_from_lessons(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Maintenance function remains client-callable';
  END IF;
END $test$;
ROLLBACK;
SELECT 'PASS: admin registry, MFA, suspension, score integrity and owner read boundaries' AS result;
