-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815053943
with base as (
  select u.id unit_id,u.program_key,u.unit_number,u.title unit_title,p.subject_title,p.subject_key,p.grade_level,p.stage_key,p.program_kind,p.track_key
  from public.mela_learning_units u join public.mela_learning_programs p on p.program_key=u.program_key
  where u.status='published' and p.active
), support as (
  select b.*,x.material_type,x.suffix,x.prefix,x.role,x.access_tier,x.display_order,x.minutes
  from base b
  cross join (values
    ('flashcards','flashcards','Recall Flashcards','revise','subscription',82,12),
    ('study_plan','studyplan','Personal Study Plan','support','subscription',84,15),
    ('teacher_guide','teacher','Educator Guide','support','subscription',86,20)
  ) x(material_type,suffix,prefix,role,access_tier,display_order,minutes)
)
insert into public.mela_learning_materials(unit_id,material_key,material_type,title,summary,pedagogical_role,language_code,access_tier,product_key,estimated_minutes,downloadable,low_bandwidth_ready,status,editorial_status,display_order,metadata)
select s.unit_id,s.program_key||'_u'||s.unit_number||'_'||s.suffix,s.material_type,s.prefix||': '||s.unit_title,
       s.prefix||' for '||s.subject_title||' — '||s.unit_title||'.',s.role,'en',s.access_tier,null,s.minutes,true,true,'published','mela_supplemental',s.display_order,
       jsonb_build_object('grade_level',s.grade_level,'stage_key',s.stage_key,'support_material',true)
from support s
on conflict(material_key) do update set title=excluded.title,summary=excluded.summary,status='published',updated_at=now();

insert into public.mela_learning_materials(unit_id,material_key,material_type,title,summary,pedagogical_role,language_code,access_tier,product_key,estimated_minutes,downloadable,low_bandwidth_ready,status,editorial_status,display_order,metadata)
select b.unit_id,b.program_key||'_u'||b.unit_number||'_parent','parent_guide','Parent / Guardian Guide: '||b.unit_title,
       'Simple ways a parent or guardian can support learning without doing the work for the learner.','support','en','subscription',null,15,true,true,'published','mela_supplemental',88,
       jsonb_build_object('grade_level',b.grade_level,'stage_key',b.stage_key,'support_material',true)
from (
  select u.id unit_id,u.program_key,u.unit_number,u.title unit_title,p.grade_level,p.stage_key
  from public.mela_learning_units u join public.mela_learning_programs p on p.program_key=u.program_key
  where p.program_kind='school_subject' and u.status='published'
) b
on conflict(material_key) do update set title=excluded.title,summary=excluded.summary,status='published',updated_at=now();

insert into public.mela_learning_materials(unit_id,material_key,material_type,title,summary,pedagogical_role,language_code,access_tier,product_key,estimated_minutes,downloadable,low_bandwidth_ready,status,editorial_status,display_order,metadata)
select u.id,p.program_key||'_u'||u.unit_number||'_lab','lab','Lab / Investigation: '||u.title,
       'Hands-on or simulated investigation for '||p.subject_title||' — '||u.title||'.','apply','en','subscription',null,45,true,true,'published','mela_supplemental',89,
       jsonb_build_object('safety_note','Use age-appropriate, low-risk materials. High-risk laboratory procedures require qualified educator supervision and institution safety rules.','grade_level',p.grade_level)
from public.mela_learning_units u join public.mela_learning_programs p on p.program_key=u.program_key
where u.status='published' and p.subject_key in ('environmental_science','general_science','physics','chemistry','biology','agriculture','information_technology','employment_technical_education','digital_literacy','digital_information_literacy','ict_support','computing_engineering','health_life_sciences','agriculture_environment')
on conflict(material_key) do update set title=excluded.title,summary=excluded.summary,status='published',updated_at=now();

insert into public.mela_learning_material_content(material_id,content_markdown,answer_key,source_notes)
select m.id,
case m.material_type
 when 'flashcards' then '# '||m.title||E'\n\nCreate or review 12 cards for this unit. Each card should use one of these forms:\n\n1. **Term → meaning**\n2. **Idea → example**\n3. **Question → short answer**\n4. **Process → next step**\n5. **Mistake → correction**\n6. **Evidence / formula / rule → when to use it**\n\n### Retrieval routine\nStudy only the question side first. Answer from memory, then check. Separate cards into **Know**, **Almost**, and **Not Yet**. Review Not Yet cards again after a short gap and return to them on later days.'
 when 'study_plan' then '# '||m.title||E'\n\n## 5-session plan\n**Session 1 — Learn:** Read the core lesson and make a short summary.\n\n**Session 2 — Practice:** Complete guided practice without copying examples.\n\n**Session 3 — Strengthen:** Use worked examples and mastery practice on weak areas.\n\n**Session 4 — Apply:** Complete the project, lab or local-context task where available.\n\n**Session 5 — Retrieve & assess:** Use flashcards, the formative quiz and the revision pack.\n\n## Spacing rule\nReturn to the unit after 1 day, then 3–7 days, then again before the next major assessment. Spend more time on errors than on material already mastered.\n\n## Evidence to record\nQuiz score, practice accuracy, hardest concept, one corrected mistake, and one example of independent application.'
 when 'teacher_guide' then '# '||m.title||E'\n\n## Teaching purpose\nHelp learners move from explanation to independent application of this unit. Mela materials are supplemental until detailed official syllabus mapping is completed.\n\n## Suggested sequence\n1. Activate prior knowledge with a short question, demonstration or local example.\n2. Teach one concept at a time using clear examples and non-examples.\n3. Ask learners to explain reasoning rather than repeat a definition.\n4. Use guided practice, then remove support gradually.\n5. Check understanding with the formative quiz and learner explanation.\n6. Use the project/lab only when it reinforces the intended learning outcome.\n\n## Differentiation\n- **Support:** shorter steps, visuals, vocabulary help, worked example, peer explanation.\n- **Core:** independent practice plus explanation.\n- **Extend:** unfamiliar case, comparison, design task, deeper source/data analysis.\n\n## Evidence to capture\nMisconceptions, learner work samples, quiz performance, participation, project evidence and the next intervention needed.\n\n## Safety / integrity\nFor science, technical and health activities, follow institution safety rules. Do not treat AI-generated content as authoritative; educators should review factual accuracy, local language and curriculum fit.'
 when 'parent_guide' then '# '||m.title||E'\n\n## How to help\n- Ask the learner to **explain** what they learned instead of giving the answer.\n- Ask for one example from home, community or everyday life.\n- Encourage a short, regular study routine instead of one long session.\n- Praise effort, correction and explanation—not only the final score.\n- If the learner is stuck, ask: *What do you know? What is the question asking? What could you try first?*\n\n## 10-minute home routine\n1. Two minutes: learner explains the unit.\n2. Four minutes: one practice question or activity.\n3. Two minutes: correct one mistake.\n4. Two minutes: choose what to review next.\n\n## When to seek help\nIf the learner repeatedly cannot explain the same prerequisite idea after several supported attempts, use Mela’s diagnostic/support features or ask the teacher for targeted help.'
 when 'lab' then '# '||m.title||E'\n\n## Purpose\nUse a safe observation, simulation, design task or hands-on investigation to connect the unit to evidence.\n\n## Investigation cycle\n1. **Question:** What are you trying to find out or demonstrate?\n2. **Prediction / design:** What do you expect, and why?\n3. **Method:** What steps, materials, data or digital tools will you use?\n4. **Safety:** Identify risks and controls before starting.\n5. **Evidence:** Record observations, measurements, screenshots, outputs, tables, diagrams or notes.\n6. **Interpret:** What does the evidence suggest? What are the limitations?\n7. **Improve:** What would you change if you repeated the task?\n\n## Safety boundary\nMela should default to low-risk household/classroom activities and simulations. Chemicals, electricity, heat, biological samples, machinery or other hazardous procedures require qualified educator supervision and institution-approved safety procedures.'
 else '# '||m.title||E'\n\nMela supplemental support material.' end,
'[]'::jsonb,
'Mela-authored supplemental support material. Educator review is required before official curriculum claims.'
from public.mela_learning_materials m
where m.material_type in ('flashcards','study_plan','teacher_guide','parent_guide','lab')
on conflict(material_id) do update set content_markdown=excluded.content_markdown,source_notes=excluded.source_notes,updated_at=now();

insert into public.mela_learning_material_translations(material_id,language_code,review_status)
select m.id,l.lang,'pending' from public.mela_learning_materials m cross join (values('am'),('om'),('ti'),('so')) l(lang)
where m.status='published'
on conflict(material_id,language_code) do nothing;
;
