-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260813090132
drop policy if exists mela_authoritative_storage_gate on storage.objects;
create policy mela_authoritative_storage_gate
on storage.objects
as restrictive
for all
to authenticated
using (
  case bucket_id
    when 'call-recordings' then public.platform_feature_available('video_calls')
    when 'career-documents' then public.platform_feature_available('career_passport')
    when 'employer-documents' then public.platform_feature_available('opportunities')
    when 'practice-submissions' then public.platform_feature_available('practice')
    when 'task-attachments' then public.platform_feature_available('earn_work')
    when 'work-submissions' then public.platform_feature_available('earn_work')
    else public.platform_feature_available('platform_live')
  end
)
with check (
  case bucket_id
    when 'call-recordings' then public.platform_feature_available('video_calls')
    when 'career-documents' then public.platform_feature_available('career_passport')
    when 'employer-documents' then public.platform_feature_available('opportunities')
    when 'practice-submissions' then public.platform_feature_available('practice')
    when 'task-attachments' then public.platform_feature_available('earn_work')
    when 'work-submissions' then public.platform_feature_available('earn_work')
    else public.platform_feature_available('platform_live')
  end
);
;
