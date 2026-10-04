-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260815053641
with program_themes as (
  select p.program_key,p.subject_key,p.subject_title,p.grade_level,p.program_kind,
    case
      when p.subject_key in ('native_language','federal_working_language','english','foreign_language','applied_communication','academic_english') then
        array['Reading & Listening','Vocabulary & Meaning','Grammar & Language Patterns','Writing & Composition','Speaking & Presentation','Literature, Media & Communication']::text[]
      when p.subject_key='mathematics' and coalesce(p.grade_level,0) between 1 and 6 then
        array['Number Sense & Operations','Patterns & Early Algebra','Shapes & Geometry','Measurement, Time & Money','Data & Chance','Problem Solving & Mathematical Communication']::text[]
      when p.subject_key='mathematics' and coalesce(p.grade_level,0) between 7 and 8 then
        array['Numbers & Rational Quantities','Algebraic Expressions & Equations','Geometry & Spatial Reasoning','Measurement & Proportional Reasoning','Data, Statistics & Probability','Multi-Step Problem Solving']::text[]
      when p.subject_key='mathematics' and coalesce(p.grade_level,0) between 9 and 10 then
        array['Algebra & Equations','Functions & Graphs','Geometry & Coordinate Reasoning','Trigonometry & Measurement','Statistics & Probability','Mathematical Modelling & Review']::text[]
      when p.subject_key='mathematics' and coalesce(p.grade_level,0) between 11 and 12 then
        array['Advanced Algebra & Functions','Sequences, Relations & Graphs','Geometry & Trigonometric Reasoning','Change, Rates & Introductory Calculus Ideas','Probability, Statistics & Data','Modelling, Synthesis & Exam Readiness']::text[]
      when p.subject_key='applied_mathematics' then
        array['Workplace Numeracy','Measurement & Estimation','Ratio, Percentage & Proportion','Costing & Financial Arithmetic','Data & Practical Calculation','Job-Context Problem Solving']::text[]
      when p.subject_key='quantitative_reasoning' then
        array['Quantitative Foundations','Functions & Relationships','Proportional & Financial Reasoning','Data Interpretation','Probability & Uncertainty','Modelling & Decision Making']::text[]
      when p.subject_key='environmental_science' then
        array['My Environment & Observation','Living Things & Habitats','Materials, Water & Everyday Science','Weather, Earth & Local Place','Health, Safety & Community','Care for Resources & Sustainability']::text[]
      when p.subject_key='moral_education' then
        array['Self, Values & Choices','Family & Community','Respect, Empathy & Cooperation','Responsibility & Honesty','Fairness, Rules & Peace','Service, Reflection & Good Citizenship']::text[]
      when p.subject_key='art' then
        array['Drawing, Line & Shape','Color, Pattern & Visual Expression','Craft, Materials & Making','Music, Rhythm & Performance','Design, Culture & Creative Communication','Creative Portfolio & Reflection']::text[]
      when p.subject_key='health_physical_education' then
        array['Movement & Coordination','Fitness & Active Living','Hygiene & Personal Health','Nutrition, Growth & Wellbeing','Safety, First Response & Risk Awareness','Teamwork, Sport & Healthy Habits']::text[]
      when p.subject_key='general_science' then
        array['Scientific Inquiry & Measurement','Life Science & Living Systems','Matter & Materials','Forces, Energy & Simple Systems','Earth, Space & Environment','Investigation, Evidence & Science Project']::text[]
      when p.subject_key='social_science' then
        array['Maps, Place & Geography','Historical Thinking & Sources','People, Culture & Society','Livelihoods, Resources & Economy','Citizenship, Institutions & Community','Local Research & Social Inquiry Project']::text[]
      when p.subject_key='civics' then
        array['Identity, Values & Community','Rights & Responsibilities','Government, Institutions & Participation','Law, Justice & Accountability','Diversity, Peace & Conflict Resolution','Civic Action & Community Project']::text[]
      when p.subject_key in ('information_technology','digital_literacy','digital_information_literacy') then
        array['Digital Devices & Systems','Files, Productivity & Collaboration','Internet, Search & Information Quality','Data, Spreadsheets & Visualization','Coding, Automation & Computational Thinking','Cybersecurity, Digital Citizenship & Responsible AI']::text[]
      when p.subject_key='employment_technical_education' then
        array['Design Process & Problem Solving','Tools, Safety & Workshop Habits','Materials & Making','Technical Drawing & Measurement','Enterprise, Work & Customer Needs','Build, Test & Improve a Practical Project']::text[]
      when p.subject_key='physics' then
        array['Measurement, Motion & Graphs','Forces & Mechanics','Work, Energy & Power','Waves, Sound & Light','Electricity, Magnetism & Circuits','Applied Physics, Investigation & Synthesis']::text[]
      when p.subject_key='chemistry' then
        array['Matter, Measurement & Particle Ideas','Atomic Structure & Chemical Bonding','Chemical Reactions & Energy','Quantitative Chemistry & Solutions','Acids, Bases & Chemical Systems','Carbon, Environment & Applied Chemistry']::text[]
      when p.subject_key='biology' then
        array['Cells & Organization','Diversity, Classification & Adaptation','Genetics, Reproduction & Inheritance','Human Biology & Health','Ecology, Environment & Interdependence','Biotechnology, Investigation & Biological Evidence']::text[]
      when p.subject_key='geography' then
        array['Maps, Location & Spatial Skills','Landforms, Climate & Physical Systems','Population, Settlement & Society','Resources, Agriculture & Economic Activity','Ethiopia, Africa & Regional Connections','Environment, Sustainability & Geographic Inquiry']::text[]
      when p.subject_key='history' then
        array['Historical Thinking & Evidence','Early Societies & Long-Term Change','Ethiopia & Africa in Historical Context','Global Connections & Transformations','Modern Change, Institutions & Society','Source Analysis, Historical Argument & Review']::text[]
      when p.subject_key='economics' then
        array['Scarcity, Choice & Economic Thinking','Markets, Demand & Supply','Production, Firms & Costs','Money, National Economy & Indicators','Public Policy, Trade & Development','Personal Finance, Data & Economic Decision Making']::text[]
      when p.subject_key='agriculture' then
        array['Agricultural Systems & Safe Practice','Soil, Crops & Plant Production','Livestock & Animal Production','Water, Climate & Natural Resources','Agribusiness, Records & Value Chains','Sustainable Agriculture, Technology & Project']::text[]
      when p.subject_key='entrepreneurship' or p.subject_key='entrepreneurship_innovation' then
        array['Problem Discovery & Customer Needs','Value Proposition & Solution Design','Business Model & Market Testing','Costing, Pricing & Cash Flow','Sales, Operations & Digital Tools','Experiment, Pitch & Responsible Growth']::text[]
      when p.subject_key='workplace_safety' then
        array['Hazards & Risk Awareness','Safe Tools, Equipment & Work Areas','Personal Protection & Hygiene','Incident Prevention & Reporting','Team Communication & Professional Conduct','Safety Improvement Project']::text[]
      when p.subject_key='ict_support' then
        array['Computer Hardware & Operating Systems','Software Installation & User Support','Networking Foundations','Troubleshooting & Documentation','Cybersecurity & Safe Support Practice','Service Desk Project & Practical Evidence']::text[]
      when p.subject_key='accounting' then
        array['Business Transactions & Records','Journals, Ledgers & Trial Balance','Cash, Receivables & Controls','Income, Expenses & Basic Statements','Spreadsheet Bookkeeping & Reconciliation','Small-Business Accounting Project']::text[]
      when p.subject_key='hospitality' then
        array['Guest Service & Communication','Hospitality Operations & Hygiene','Food, Safety & Service Basics','Tourism Products & Local Destinations','Digital Promotion & Customer Experience','Hospitality Service Project']::text[]
      when p.subject_key='critical_thinking' then
        array['Claims, Reasons & Evidence','Arguments & Logical Structure','Bias, Assumptions & Fallacies','Decision Making Under Uncertainty','Problem Framing & Alternative Explanations','Critical Analysis Project']::text[]
      when p.subject_key='research_methods' then
        array['Research Questions & Problems','Searching Literature & Evaluating Sources','Study Design & Sampling','Data Collection & Research Ethics','Analysis, Interpretation & Citation','Research Proposal & Academic Integrity']::text[]
      when p.subject_key='data_statistics' then
        array['Data Types & Measurement','Describing Data','Visualization & Communication','Probability & Uncertainty','Relationships, Comparisons & Inference Ideas','Data Project & Evidence-Based Decision Making']::text[]
      when p.subject_key='career_professional' then
        array['Career Direction & Self-Assessment','CV, Portfolio & Digital Identity','Professional Communication','Interviewing & Opportunity Search','Teamwork, Leadership & Workplace Habits','Career Action Plan & Evidence Portfolio']::text[]
      when p.subject_key='computing_engineering' then
        array['Computational Thinking & Programming','Data Structures & Problem Solving','Computer Systems & Networks','Data, AI & Automation','Engineering Design & Testing','Team Software/Engineering Project']::text[]
      when p.subject_key='business_economics' then
        array['Business & Economic Foundations','Accounting & Financial Reasoning','Markets, Customers & Strategy','Operations, Management & People','Data, Finance & Decision Making','Business Analysis & Venture Project']::text[]
      when p.subject_key='health_life_sciences' then
        array['Scientific Foundations for Health','Human Biology & Health Systems','Evidence, Measurement & Health Data','Ethics, Communication & Safety','Research Literacy & Public Health Thinking','Health/Life Science Inquiry Project']::text[]
      when p.subject_key='agriculture_environment' then
        array['Agricultural & Environmental Systems','Soil, Water & Production','Climate, Ecology & Sustainability','Data, Technology & Resource Management','Agribusiness & Value Chains','Applied Agriculture/Environment Project']::text[]
      when p.subject_key='social_humanities' then
        array['Society, Culture & Human Inquiry','History, Change & Institutions','Writing, Argument & Interpretation','Qualitative Research & Evidence','Policy, Ethics & Public Problems','Social/Humanities Research Project']::text[]
      when p.subject_key='education_teaching' then
        array['How Learning Happens','Learning Objectives & Lesson Design','Assessment for Learning','Inclusive Teaching & Learner Support','Educational Technology & AI','Teaching Portfolio & Classroom Inquiry']::text[]
      else array['Foundations & Key Vocabulary','Core Concepts','Guided Application','Problem Solving & Practice','Project, Evidence & Communication','Review, Reflection & Mastery']::text[]
    end themes
  from public.mela_learning_programs p where p.active
), expanded as (
  select pt.*,u.unit_number,u.title
  from program_themes pt
  cross join lateral unnest(pt.themes) with ordinality as u(title,unit_number)
)
insert into public.mela_learning_units(program_key,unit_number,title,description,learning_outcomes,status,official_alignment_status,estimated_hours,display_order,metadata)
select e.program_key,e.unit_number,e.title,
       'Build '||case when e.grade_level is null then 'learner' else 'Grade '||e.grade_level end||'-appropriate understanding of '||e.title||' in '||e.subject_title||' through explanation, examples, practice, application and reflection.',
       jsonb_build_array(
         'Explain the key ideas and vocabulary in '||e.title||'.',
         'Apply the ideas in '||e.title||' to age-appropriate or study-level problems.',
         'Communicate reasoning, evidence or process clearly.',
         'Complete a practical task, investigation or reflection connected to '||e.title||'.'
       ),
       'published','supplemental_pending_official_mapping',
       case when e.program_kind='school_subject' and coalesce(e.grade_level,0)<=6 then 2.5 when e.program_kind='school_subject' then 4 else 6 end,
       e.unit_number*100,
       jsonb_build_object('editorial_note','Mela supplemental unit; detailed official syllabus mapping pending educator review','source_program_kind',e.program_kind)
from expanded e
on conflict(program_key,unit_number) do update set title=excluded.title,description=excluded.description,learning_outcomes=excluded.learning_outcomes,status='published',official_alignment_status=excluded.official_alignment_status,estimated_hours=excluded.estimated_hours,display_order=excluded.display_order,metadata=excluded.metadata,updated_at=now();

with base as (
  select u.id unit_id,u.program_key,u.unit_number,u.title unit_title,p.subject_title,p.subject_key,p.grade_level,p.stage_key,p.program_kind,p.track_key
  from public.mela_learning_units u join public.mela_learning_programs p on p.program_key=u.program_key
  where u.status='published' and p.active
), mats as (
  select b.*,x.material_type,x.material_suffix,x.title_prefix,x.pedagogical_role,x.access_tier,x.display_order,x.minutes
  from base b
  cross join (values
    ('core_lesson','lesson','Core Lesson','teach','free',10,25),
    ('lesson_summary','summary','Quick Summary','revise','free',20,10),
    ('guided_practice','practice','Guided Practice','practice','free',30,20),
    ('quiz','quiz','Formative Quiz','assess','free',40,15),
    ('worked_examples','worked','Worked Examples & Model Responses','teach','subscription',50,25),
    ('mastery_practice','mastery','Mastery Practice','practice','subscription',60,30),
    ('project','project','Application Project','apply','subscription',70,45),
    ('revision_pack','revision','Revision Pack','revise','subscription',80,30)
  ) as x(material_type,material_suffix,title_prefix,pedagogical_role,access_tier,display_order,minutes)
)
insert into public.mela_learning_materials(unit_id,material_key,material_type,title,summary,pedagogical_role,language_code,access_tier,product_key,estimated_minutes,downloadable,low_bandwidth_ready,status,editorial_status,display_order,metadata)
select m.unit_id,m.program_key||'_u'||m.unit_number||'_'||m.material_suffix,m.material_type,
       m.title_prefix||': '||m.unit_title,
       m.title_prefix||' for '||m.subject_title||' — '||m.unit_title||'.',
       m.pedagogical_role,'en',m.access_tier,
       null,m.minutes,true,true,'published','mela_supplemental',m.display_order,
       jsonb_build_object('grade_level',m.grade_level,'stage_key',m.stage_key,'track_key',m.track_key,'alignment_note','Supplemental until detailed educator-reviewed syllabus mapping')
from mats m
on conflict(material_key) do update set title=excluded.title,summary=excluded.summary,pedagogical_role=excluded.pedagogical_role,access_tier=excluded.access_tier,estimated_minutes=excluded.estimated_minutes,status='published',metadata=excluded.metadata,updated_at=now();

insert into public.mela_learning_materials(unit_id,material_key,material_type,title,summary,pedagogical_role,language_code,access_tier,product_key,estimated_minutes,downloadable,low_bandwidth_ready,status,editorial_status,display_order,metadata)
select u.id,p.program_key||'_exam_master','mock_exam','Exam Master: '||p.subject_title,
       'Premium Grade 12 timed mock, answer review and exam-readiness pack for '||p.subject_title||'.','assess','en','one_time','grade12_exam_master',90,true,true,'published','mela_supplemental',95,
       jsonb_build_object('grade_level',12,'exam_prep',true,'alignment_note','Must be mapped to current official exam scope before public exam claims')
from public.mela_learning_programs p join public.mela_learning_units u on u.program_key=p.program_key and u.unit_number=6
where p.grade_level=12 and p.program_kind='school_subject'
on conflict(material_key) do update set title=excluded.title,summary=excluded.summary,access_tier=excluded.access_tier,product_key=excluded.product_key,status='published',metadata=excluded.metadata,updated_at=now();

insert into public.mela_learning_materials(unit_id,material_key,material_type,title,summary,pedagogical_role,language_code,access_tier,product_key,estimated_minutes,downloadable,low_bandwidth_ready,status,editorial_status,display_order,metadata)
select u.id,p.program_key||'_premium_capstone','project','Premium Capstone: '||p.subject_title,
       'Premium applied capstone with evidence, rubric and portfolio guidance.','apply','en','one_time','career_certificate_pack',180,true,true,'published','mela_supplemental',96,
       jsonb_build_object('capstone',true,'credential_note','Completion credential only when assessment and evidence rules are satisfied')
from public.mela_learning_programs p join public.mela_learning_units u on u.program_key=p.program_key and u.unit_number=6
where p.program_kind in ('tvet_pathway','university_pathway')
on conflict(material_key) do update set title=excluded.title,summary=excluded.summary,access_tier=excluded.access_tier,product_key=excluded.product_key,status='published',metadata=excluded.metadata,updated_at=now();

insert into public.mela_learning_material_content(material_id,content_markdown,answer_key,source_notes)
select m.id,
  case m.material_type
    when 'core_lesson' then '# '||m.title||E'\n\n**Purpose**\nThis lesson builds a clear foundation in **'||u.title||'** for **'||p.subject_title||'**. It is a Mela supplemental lesson until an educator maps it to the exact official unit/chapter used by the learner.\n\n## Learn\n1. Start by identifying the key words and ideas connected to '||u.title||'.\n2. Connect each new idea to something the learner already knows from school, home, community or prior study.\n3. Use an example, diagram, short explanation, demonstration or calculation appropriate to the subject.\n4. Explain *why* the answer, process or interpretation makes sense—not only what the answer is.\n\n## Mela learning routine\n- **Notice:** What do you observe?\n- **Name:** What concept or rule is involved?\n- **Try:** Apply it to a simple example.\n- **Explain:** Describe your reasoning in your own words.\n- **Transfer:** Use the idea in a new or local context.\n\n## Example / activity\nChoose one real situation related to '||u.title||' and describe, calculate, investigate, design or interpret it using the methods of '||p.subject_title||'. For younger learners, use familiar objects, pictures, movement or stories. For older learners, use data, evidence, calculations, sources, experiments or structured argument where appropriate.\n\n## Check yourself\n- Can I explain the main idea without copying the lesson?\n- Can I give an example?\n- Can I solve or analyze a new case?\n- Can I explain how I checked my work?\n\n## Local connection\nFind one example from Ethiopia, your community, school, household, workplace or field of study that connects to this unit. Record what you learned and one question you still have.'
    when 'lesson_summary' then '# '||m.title||E'\n\n## What to remember\n- Name the **3–5 most important ideas** from '||u.title||'.\n- Write one sentence for each idea in your own words.\n- Record essential vocabulary, symbols, formulas, dates, evidence types, processes or safety rules relevant to the subject.\n- Add one example and one common mistake to avoid.\n\n## 60-second recall\nClose the lesson and explain the unit aloud or on paper from memory. Reopen it, compare, and correct anything missing.\n\n## Mastery check\nYou are ready to move on when you can explain, apply and check the core idea without needing to copy a model answer.'
    when 'guided_practice' then '# '||m.title||E'\n\nComplete these in order. Use your lesson notes only after trying independently.\n\n1. **Recall:** List or define the key ideas in '||u.title||'.\n2. **Identify:** Give two examples and one non-example.\n3. **Apply:** Solve, analyze, describe, classify, interpret or demonstrate a straightforward case.\n4. **Explain:** Show your reasoning, evidence or process step by step.\n5. **Transfer:** Create or solve a new case connected to your school, community, household, workplace or field.\n6. **Reflect:** What part was hardest, and what would you do differently next time?\n\n**Self-score:** 0 = not yet, 1 = with help, 2 = independently, 3 = can explain to someone else.'
    when 'quiz' then '# '||m.title||E'\n\nAnswer without looking at the lesson first.\n\n1. In your own words, what is the central idea of '||u.title||'?\n2. Give one accurate example and explain why it fits.\n3. What is one common error, misconception or weak approach in this topic?\n4. Apply the unit to a new situation and show your reasoning.\n5. What evidence, calculation, observation, source, rule or check would make your answer stronger?\n\n**Scoring guide:** 2 points per question. Full credit requires a relevant answer plus reasoning/evidence, not a copied phrase.'
    when 'worked_examples' then '# '||m.title||E'\n\n## Model process\nUse this repeatable method for '||u.title||':\n\n1. **Understand the task.** What is being asked? What information or evidence is available?\n2. **Choose the idea or method.** Identify the rule, concept, source, procedure, formula, strategy or design principle that fits.\n3. **Work step by step.** Keep each step visible so mistakes can be found.\n4. **Explain the reasoning.** State why each important step is valid.\n5. **Check.** Test units, logic, evidence quality, plausibility, safety, source reliability or alternative explanations as appropriate.\n6. **Improve the response.** Make it clearer, more precise and easier for another learner to follow.\n\n## Model response A\nStart with a simple case from the learner’s level. Label the information, select a method, complete it step by step, and finish with a one-sentence check.\n\n## Model response B\nUse a less familiar or real-world case. Compare two possible approaches and explain why one is stronger.\n\n## Your turn\nCreate one similar example, solve/analyze it, then change one condition and solve/analyze it again.'
    when 'mastery_practice' then '# '||m.title||E'\n\n## Level 1 — Foundation\n1. Define two key terms.\n2. Identify or classify two simple examples.\n3. Reproduce one basic process, calculation, explanation or representation.\n\n## Level 2 — Apply\n4. Solve or analyze a new example.\n5. Explain *why* the method works.\n6. Compare two cases and identify the important difference.\n7. Correct a deliberately weak or incomplete answer.\n\n## Level 3 — Transfer\n8. Apply the idea to an Ethiopian or local context.\n9. Create a problem, investigation, design task or argument using '||u.title||'.\n10. Teach the idea to another learner using an example, diagram, demonstration, evidence or step-by-step explanation.\n\nTarget: complete at least 8/10 independently before marking the unit mastered.'
    when 'project' then '# '||m.title||E'\n\n## Challenge\nUse '||u.title||' to investigate, solve, explain, design, build or improve something connected to real life.\n\n## Required evidence\n- A clear question or problem.\n- A short plan.\n- Evidence of the work: notes, calculations, observations, sources, photos, diagrams, code, prototype, table or written analysis as appropriate.\n- A final explanation of what you found or created.\n- A reflection: what worked, what did not, and what you would improve.\n\n## Suggested local contexts\nSchool, household, community, small business, agriculture, environment, transport, health, technology, culture or the learner’s field of study.\n\n## Rubric\n25% understanding • 25% application • 20% evidence • 20% communication • 10% reflection/improvement.'
    when 'revision_pack' then '# '||m.title||E'\n\n## Revision sequence\n1. Recall the unit from memory in five bullet points.\n2. Review key vocabulary, rules, processes, formulas, evidence or concepts.\n3. Complete one easy, two medium and one challenging application.\n4. Correct one common mistake.\n5. Explain the unit aloud in two minutes.\n6. Write a one-page revision sheet with only the information you would need the day before an assessment.\n\n## Red / Amber / Green\n- **Red:** I cannot yet explain or apply it.\n- **Amber:** I can do it with prompts.\n- **Green:** I can do it independently and explain why.\n\nRepeat practice only on Red/Amber areas.'
    when 'mock_exam' then '# '||m.title||E'\n\n## Before the timed attempt\nConfirm the current official exam scope with Mela’s reviewed exam mapping. This pack must not be treated as an official past paper unless the source is explicitly identified and licensed.\n\n## Timed mock structure\n- Section A: core recall and understanding.\n- Section B: application and multi-step problems.\n- Section C: reasoning, interpretation, synthesis or extended response.\n\n## After the attempt\n1. Score using the reviewed marking guide.\n2. Tag each error: knowledge gap, method error, careless error, time issue or misunderstanding.\n3. Relearn only the weak areas.\n4. Retake a parallel set after spaced practice.\n\n## Readiness evidence\nTrack accuracy, completion time, confidence and repeated-error rate across attempts.'
    else '# '||m.title||E'\n\nUse this Mela material to learn, practice, apply and reflect on '||u.title||'.'
  end,
  case when m.material_type='quiz' then jsonb_build_array(
      jsonb_build_object('question',1,'expected','Clear explanation of the central idea using relevant vocabulary.'),
      jsonb_build_object('question',2,'expected','Relevant example plus explanation of why it fits.'),
      jsonb_build_object('question',3,'expected','Plausible misconception/error and a correction.'),
      jsonb_build_object('question',4,'expected','Correct application to a new case with visible reasoning.'),
      jsonb_build_object('question',5,'expected','Appropriate check, evidence, calculation, source or validation method.')
    ) else '[]'::jsonb end,
  'Mela-authored supplemental material. Do not label as official Ethiopian curriculum content until detailed educator-reviewed mapping is completed.'
from public.mela_learning_materials m
join public.mela_learning_units u on u.id=m.unit_id
join public.mela_learning_programs p on p.program_key=u.program_key
on conflict(material_id) do update set content_markdown=excluded.content_markdown,answer_key=excluded.answer_key,source_notes=excluded.source_notes,updated_at=now();

insert into public.mela_learning_material_translations(material_id,language_code,review_status)
select m.id,l.lang,'pending'
from public.mela_learning_materials m
cross join (values('am'),('om'),('ti'),('so')) l(lang)
where m.status='published'
on conflict(material_id,language_code) do nothing;
;
