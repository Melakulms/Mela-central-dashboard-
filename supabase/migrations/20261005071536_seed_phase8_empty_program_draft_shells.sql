-- Phase 8 preparation: create non-public, non-approved structured draft shells for every empty active program.
do $phase8$
declare
  v_actor uuid;
begin
  select au.user_id into v_actor
  from admin.admin_users au
  join admin.roles r on r.id=au.role_id
  where au.active and r.key='super_admin'
  order by au.created_at
  limit 1;

  if v_actor is null then
    raise exception 'active super-admin actor required to seed content draft shells';
  end if;

  insert into admin.content_drafts(
    entity_type, program_key, language_code, title, payload, status, created_by, updated_by
  )
  select
    'program_seed',
    i.program_key,
    'en',
    i.title || ' launch content seed',
    jsonb_build_object(
      'program_key', i.program_key,
      'stage_key', i.stage_key,
      'grade_level', i.grade_level,
      'track_key', i.track_key,
      'subject_key', i.subject_key,
      'subject_title', i.subject_title,
      'program_title', i.title,
      'source_status', 'needs_source_verification',
      'review_status', 'needs_qualified_review',
      'required_sections', jsonb_build_array(
        'learning_objectives',
        'lesson_explanation',
        'ethiopian_context_examples',
        'worked_practice',
        'answer_explanations',
        'accessibility_text_alternatives',
        'source_attribution',
        'translation_notes'
      ),
      'learning_objectives', jsonb_build_array(),
      'lesson_explanation', '',
      'ethiopian_context_examples', jsonb_build_array(),
      'worked_practice', jsonb_build_array(),
      'answer_explanations', jsonb_build_array(),
      'accessibility_text_alternatives', jsonb_build_array(),
      'source_attribution', jsonb_build_array(),
      'translation_notes', '',
      'publication_blocked_reason', 'Complete content plus qualified subject and language review required'
    ),
    'draft',
    v_actor,
    v_actor
  from admin.content_program_inventory i
  where i.active and not i.has_content
    and not exists (
      select 1 from admin.content_drafts d
      where d.entity_type='program_seed'
        and d.program_key=i.program_key
        and d.status <> 'archived'
    );
end
$phase8$;
