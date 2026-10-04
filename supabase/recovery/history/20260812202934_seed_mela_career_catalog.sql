-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812202934
-- Seed Mela-owned career catalog. No fake external partnerships or live jobs.

insert into public.career_paths
(category,title,partner_organization,badge_title,level_info,description,unlocked_opportunities)
select v.category::public.launch_category, v.title, 'Mela Career Lab', v.badge_title,
       '5 Modules • 20 Lessons', v.description, v.unlocked
from (values
('Business & Finance','Banking & Financial Services','Mela Banking Ready','Build practical skills for banking, finance operations, customer service and financial analysis.','Entry-level banking, finance internships and customer service roles'),
('Technology','Software, Data & AI','Mela Digital Talent','Build foundations in digital tools, data, programming and applied artificial intelligence.','Technology internships, junior digital roles and project opportunities'),
('Health & Sciences','Health & Clinical Support','Mela Health Ready','Develop workplace-ready health support, communication, safety and health-data skills.','Health support internships, NGO health projects and clinical support roles'),
('Agriculture & Environment','Modern Agriculture & Agribusiness','Mela Agribusiness Ready','Learn modern agriculture, farm business, sustainability and agribusiness operations.','Agribusiness internships, farm operations and development-project opportunities'),
('Education & Social Sciences','Education & Community Development','Mela Community Impact','Strengthen facilitation, research, education and community-development capabilities.','Education internships, research assistant roles and NGO opportunities'),
('Skilled Trades','Technical Trades & Maintenance','Mela Technical Ready','Develop safety, maintenance, electrical and technical problem-solving foundations.','Technical apprenticeships, maintenance roles and industrial placements'),
('Creative & Media','Digital Media & Creative Production','Mela Creative Talent','Build portfolio-ready skills in design, content, video and digital communication.','Creative gigs, media internships and digital marketing opportunities'),
('Manufacturing & Logistics','Manufacturing, Supply Chain & Logistics','Mela Operations Ready','Build practical capability in inventory, quality, warehousing and supply-chain operations.','Industrial internships, warehouse roles and logistics opportunities')
) as v(category,title,badge_title,description,unlocked)
where not exists (select 1 from public.career_paths cp where cp.title=v.title);

with module_seed(path_title,module_order,module_title,is_proctored,pass_score) as (values
('Banking & Financial Services',1,'Finance & Banking Foundations',false,70),
('Banking & Financial Services',2,'Customer Service & Professional Communication',false,70),
('Banking & Financial Services',3,'Excel & Financial Analysis',false,70),
('Banking & Financial Services',4,'Banking Operations & Compliance Basics',false,70),
('Banking & Financial Services',5,'Banking Career Readiness Assessment',true,75),
('Software, Data & AI',1,'Digital & Computing Foundations',false,70),
('Software, Data & AI',2,'Data Literacy & Analysis',false,70),
('Software, Data & AI',3,'Programming Foundations',false,70),
('Software, Data & AI',4,'Applied AI & Responsible Technology',false,70),
('Software, Data & AI',5,'Digital Talent Assessment',true,75),
('Health & Clinical Support',1,'Healthcare Workplace Foundations',false,70),
('Health & Clinical Support',2,'Patient Communication',false,70),
('Health & Clinical Support',3,'Safety & Infection Prevention',false,70),
('Health & Clinical Support',4,'Health Records & Data Basics',false,70),
('Health & Clinical Support',5,'Health Career Readiness Assessment',true,75),
('Modern Agriculture & Agribusiness',1,'Agriculture & Agribusiness Foundations',false,70),
('Modern Agriculture & Agribusiness',2,'Crop & Farm Operations',false,70),
('Modern Agriculture & Agribusiness',3,'Farm Records & Basic Finance',false,70),
('Modern Agriculture & Agribusiness',4,'Sustainable Agriculture & Markets',false,70),
('Modern Agriculture & Agribusiness',5,'Agribusiness Readiness Assessment',true,75),
('Education & Community Development',1,'Education & Development Foundations',false,70),
('Education & Community Development',2,'Facilitation & Lesson Planning',false,70),
('Education & Community Development',3,'Research & Data Collection',false,70),
('Education & Community Development',4,'Community Engagement & Safeguarding',false,70),
('Education & Community Development',5,'Community Impact Assessment',true,75),
('Technical Trades & Maintenance',1,'Workplace Safety & Tools',false,70),
('Technical Trades & Maintenance',2,'Technical Drawing & Measurement',false,70),
('Technical Trades & Maintenance',3,'Electrical & Mechanical Basics',false,70),
('Technical Trades & Maintenance',4,'Maintenance & Troubleshooting',false,70),
('Technical Trades & Maintenance',5,'Technical Readiness Assessment',true,75),
('Digital Media & Creative Production',1,'Creative Career Foundations',false,70),
('Digital Media & Creative Production',2,'Graphic Design & Visual Communication',false,70),
('Digital Media & Creative Production',3,'Content & Video Production',false,70),
('Digital Media & Creative Production',4,'Digital Marketing & Portfolio Building',false,70),
('Digital Media & Creative Production',5,'Creative Talent Assessment',true,75),
('Manufacturing, Supply Chain & Logistics',1,'Operations & Manufacturing Foundations',false,70),
('Manufacturing, Supply Chain & Logistics',2,'Inventory & Warehouse Operations',false,70),
('Manufacturing, Supply Chain & Logistics',3,'Quality & Continuous Improvement',false,70),
('Manufacturing, Supply Chain & Logistics',4,'Supply Chain & Logistics Basics',false,70),
('Manufacturing, Supply Chain & Logistics',5,'Operations Readiness Assessment',true,75)
)
insert into public.path_modules(career_path_id,module_order,title,lessons_count,is_proctored_assessment,pass_score)
select cp.id, ms.module_order, ms.module_title, 4, ms.is_proctored, ms.pass_score
from module_seed ms
join public.career_paths cp on cp.title=ms.path_title
on conflict (career_path_id,module_order) do nothing;

insert into public.skills(name,category)
select s.name,s.category
from (values
('Financial Literacy','Business & Finance'),('Excel for Finance','Business & Finance'),('Customer Service','Business & Finance'),('Banking Operations','Business & Finance'),
('Digital Literacy','Technology'),('Data Analysis','Technology'),('Python Programming','Technology'),('AI Fundamentals','Technology'),
('Patient Communication','Health & Sciences'),('Health Data Basics','Health & Sciences'),('Infection Prevention','Health & Sciences'),('First Aid','Health & Sciences'),
('Agribusiness Basics','Agriculture & Environment'),('Crop Production','Agriculture & Environment'),('Farm Record Keeping','Agriculture & Environment'),('Sustainable Agriculture','Agriculture & Environment'),
('Lesson Planning','Education & Social Sciences'),('Facilitation','Education & Social Sciences'),('Research Methods','Education & Social Sciences'),('Community Engagement','Education & Social Sciences'),
('Workplace Safety','Skilled Trades'),('Electrical Basics','Skilled Trades'),('Mechanical Maintenance','Skilled Trades'),('Technical Drawing','Skilled Trades'),
('Graphic Design','Creative & Media'),('Content Creation','Creative & Media'),('Video Editing','Creative & Media'),('Digital Marketing','Creative & Media'),
('Inventory Management','Manufacturing & Logistics'),('Quality Control','Manufacturing & Logistics'),('Supply Chain Basics','Manufacturing & Logistics'),('Warehouse Operations','Manufacturing & Logistics')
) s(name,category)
on conflict (name) do update set category=excluded.category;

insert into public.badges(code,title,description,tier_rank)
values
('MELA-BIZ-READY','Mela Banking Ready','Career-path badge for foundational banking and finance readiness.',1),
('MELA-DIGITAL-TALENT','Mela Digital Talent','Career-path badge for foundational technology, data and AI readiness.',1),
('MELA-HEALTH-READY','Mela Health Ready','Career-path badge for foundational health-sector readiness.',1),
('MELA-AGRIBIZ-READY','Mela Agribusiness Ready','Career-path badge for modern agriculture and agribusiness readiness.',1),
('MELA-COMMUNITY-IMPACT','Mela Community Impact','Career-path badge for education and community-development readiness.',1),
('MELA-TECHNICAL-READY','Mela Technical Ready','Career-path badge for skilled-trade and technical readiness.',1),
('MELA-CREATIVE-TALENT','Mela Creative Talent','Career-path badge for creative and digital-media readiness.',1),
('MELA-OPS-READY','Mela Operations Ready','Career-path badge for manufacturing, logistics and operations readiness.',1)
on conflict (code) do update set title=excluded.title, description=excluded.description, tier_rank=excluded.tier_rank;

-- Starter assessment definitions. These remain draft until reviewed and question banks are approved.
insert into public.skill_assessments(skill_id,category,title,description,duration_minutes,pass_score,max_attempts,is_proctored,status)
select s.id, x.category::public.launch_category, x.title, x.description, 30, 75, 3, true, 'draft'
from (values
('Banking Operations','Business & Finance','Banking Career Readiness Assessment','Measures foundational banking operations, customer service and finance readiness.'),
('Digital Literacy','Technology','Digital Talent Readiness Assessment','Measures digital literacy, data reasoning and technology readiness.'),
('Patient Communication','Health & Sciences','Health Career Readiness Assessment','Measures healthcare communication, safety and support-work readiness.'),
('Agribusiness Basics','Agriculture & Environment','Agribusiness Readiness Assessment','Measures foundational agriculture, farm-business and market readiness.'),
('Facilitation','Education & Social Sciences','Community Impact Readiness Assessment','Measures facilitation, research and community-engagement readiness.'),
('Workplace Safety','Skilled Trades','Technical Career Readiness Assessment','Measures safety, technical reasoning and maintenance readiness.'),
('Content Creation','Creative & Media','Creative Talent Readiness Assessment','Measures creative communication, production and digital portfolio readiness.'),
('Inventory Management','Manufacturing & Logistics','Operations Readiness Assessment','Measures inventory, quality, warehousing and supply-chain readiness.')
) x(skill_name,category,title,description)
join public.skills s on s.name=x.skill_name
where not exists (select 1 from public.skill_assessments a where a.title=x.title);

;
