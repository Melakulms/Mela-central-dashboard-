-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260814183246
create table if not exists public.audience_learning_tracks(
  track_key text primary key,
  stage_key text not null references public.education_audience_stages(stage_key) on delete cascade,
  title text not null,
  description text not null,
  focus_areas text[] not null default '{}',
  track_type text not null check(track_type in ('foundation','stem','communication','digital_ai','coding_data','creativity','life_skills','exploration','transition','academic','entrepreneurship')),
  content_status text not null default 'development' check(content_status in ('development','educator_review','active')),
  display_order smallint not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.audience_learning_tracks(track_key,stage_key,title,description,focus_areas,track_type,content_status,display_order) values
('g1_6_numeracy_logic','school_1_6','Numeracy & Logic','Build number sense, patterns, reasoning and everyday problem solving.',array['number sense','patterns','logic','problem solving'],'foundation','development',10),
('g1_6_science_discovery','school_1_6','Science & Discovery','Explore the natural world through observation, questions and simple investigations.',array['observation','science habits','nature','experiments'],'stem','development',20),
('g1_6_reading_communication','school_1_6','Reading & Communication','Strengthen comprehension, expression, listening and clear communication.',array['reading','comprehension','speaking','writing'],'communication','development',30),
('g1_6_digital_safety','school_1_6','Digital Foundations & Safety','Learn how digital tools work and how to use them safely and responsibly.',array['digital basics','online safety','privacy','responsible use'],'digital_ai','development',40),
('g1_6_creativity_making','school_1_6','Creativity & Making','Use drawing, storytelling, design and hands-on projects to create and explain ideas.',array['creativity','design','storytelling','making'],'creativity','development',50),
('g1_6_ai_awareness','school_1_6','AI Awareness','Understand in simple terms what AI can and cannot do and how to use it safely with adult guidance.',array['AI basics','safe AI use','questions','critical thinking'],'digital_ai','development',60),

('g7_8_stem','school_7_8','STEM Foundations','Strengthen mathematics, science reasoning and structured problem solving.',array['mathematics','science','reasoning','problem solving'],'stem','development',10),
('g7_8_communication','school_7_8','Communication & Research','Learn to explain ideas, find information, compare sources and present clearly.',array['research','writing','presentation','source evaluation'],'communication','development',20),
('g7_8_digital','school_7_8','Digital Skills & Online Safety','Build practical digital skills, privacy awareness and responsible online behavior.',array['productivity','privacy','cyber safety','digital citizenship'],'digital_ai','development',30),
('g7_8_coding','school_7_8','Coding & Computational Thinking','Learn sequencing, decomposition, patterns and introductory programming concepts.',array['algorithms','coding','decomposition','debugging'],'coding_data','development',40),
('g7_8_ai','school_7_8','AI Literacy','Learn how AI systems are used, where they can fail and how to ask better questions safely.',array['AI literacy','prompting basics','bias','verification'],'digital_ai','development',50),
('g7_8_explore','school_7_8','Subject & Future Explorer','Connect interests, school subjects and broad future education/career fields without locking into a job choice.',array['interests','subjects','pathways','reflection'],'exploration','development',60),

('g9_10_stem','school_9_10','STEM & Problem Solving','Develop stronger analytical reasoning across mathematics, science and real-world problems.',array['STEM','analysis','reasoning','problem solving'],'stem','development',10),
('g9_10_digital_ai','school_9_10','Digital & AI Skills','Use digital and AI tools critically, safely and productively for learning and projects.',array['AI literacy','digital productivity','verification','online safety'],'digital_ai','development',20),
('g9_10_coding_data','school_9_10','Coding & Data Foundations','Build introductory programming, spreadsheet, data reasoning and computational-thinking skills.',array['coding','data','spreadsheets','computational thinking'],'coding_data','development',30),
('g9_10_academic','school_9_10','Communication & Academic Skills','Improve study strategy, research, writing, presentation and evidence-based explanation.',array['study skills','research','writing','presentation'],'academic','development',40),
('g9_10_projects','school_9_10','Projects & Career Exploration','Complete projects while exploring broad fields such as technology, health, business, agriculture, creative work and skilled trades.',array['projects','career fields','reflection','portfolio'],'exploration','development',50),
('g9_10_entrepreneurship','school_9_10','Entrepreneurship & Everyday Financial Literacy','Learn value creation, budgeting concepts and responsible money basics without financial-product selling or work-market pressure.',array['entrepreneurship','budgeting','value creation','responsible money habits'],'entrepreneurship','development',60),

('g11_12_academic','school_11_12','Academic & Exam Strategy','Strengthen study planning, reasoning, research and exam preparation.',array['study strategy','exam preparation','research','academic communication'],'academic','development',10),
('g11_12_digital_ai','school_11_12','Digital & AI Productivity','Use AI and digital tools responsibly for learning, projects and transition preparation.',array['AI productivity','digital tools','verification','responsible use'],'digital_ai','development',20),
('g11_12_research','school_11_12','Research & Communication','Build evidence-based writing, presentations, source evaluation and project communication.',array['research','writing','presentation','source evaluation'],'communication','development',30),
('g11_12_transition','school_11_12','University & TVET Preparation','Compare post-secondary pathways, entry expectations and practical next-step planning.',array['university','TVET','pathway comparison','transition planning'],'transition','development',40),
('g11_12_scholarship','school_11_12','Scholarship Readiness','Prepare strong profiles, evidence, documents and application habits for verified scholarships.',array['scholarships','documents','applications','profile building'],'transition','development',50),
('g11_12_career','school_11_12','Career Readiness','Explore career fields, build a Transition Passport and prepare for verified skill evidence.',array['career exploration','Career Passport','verified skills','projects'],'exploration','development',60),
('g11_12_enterprise','school_11_12','Entrepreneurship & Project Skills','Learn project planning, teamwork, value creation and responsible financial basics.',array['projects','teamwork','entrepreneurship','financial literacy'],'entrepreneurship','development',70)
on conflict(track_key) do update set title=excluded.title,description=excluded.description,focus_areas=excluded.focus_areas,track_type=excluded.track_type,content_status=excluded.content_status,display_order=excluded.display_order,updated_at=now();

alter table public.audience_learning_tracks enable row level security;
create policy audience_learning_tracks_read on public.audience_learning_tracks for select to anon,authenticated using(true);
create policy mela_gate_platform_live on public.audience_learning_tracks as restrictive for all to anon,authenticated using(public.platform_feature_available('platform_live')) with check(public.platform_feature_available('platform_live'));
revoke all on public.audience_learning_tracks from anon,authenticated;
grant select on public.audience_learning_tracks to anon,authenticated;
create index if not exists audience_learning_tracks_stage_idx on public.audience_learning_tracks(stage_key,display_order);
;
