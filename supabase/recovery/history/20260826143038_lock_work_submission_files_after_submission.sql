-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260826143038
CREATE OR REPLACE FUNCTION private.can_modify_work_submission_storage(p_name text)
RETURNS boolean
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_uid uuid := (select auth.uid());
  v_parts text[] := storage.foldername(p_name);
  v_contract_id uuid;
begin
  if v_uid is null or coalesce(array_length(v_parts,1),0) < 2 then return false; end if;
  if private.is_admin_user() then return true; end if;
  begin v_contract_id := v_parts[2]::uuid; exception when invalid_text_representation then return false; end;
  return exists (
    select 1
    from public.freelance_contracts c
    where c.id=v_contract_id
      and c.freelancer_id=v_uid
      and not exists (
        select 1 from public.task_milestones m
        where m.contract_id=c.id
          and m.status in ('submitted','approved','paid')
      )
  );
end;
$function$;

DROP POLICY IF EXISTS "Mela work submissions update" ON storage.objects;
CREATE POLICY "Mela work submissions update" ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id='work-submissions' AND private.can_modify_work_submission_storage(name))
WITH CHECK (bucket_id='work-submissions' AND private.can_modify_work_submission_storage(name));

DROP POLICY IF EXISTS "Mela work submissions delete" ON storage.objects;
CREATE POLICY "Mela work submissions delete" ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id='work-submissions' AND private.can_modify_work_submission_storage(name));
;
