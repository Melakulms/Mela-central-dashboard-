-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812205053
with keys(assessment_title, question_order, correct_answer, explanation) as (
values
('Banking Career Readiness Assessment',1,'B','Commercial banks commonly accept deposits and provide payment, savings and credit services.'),
('Banking Career Readiness Assessment',2,'A','Transaction or current accounts are intended for frequent day-to-day money movement.'),
('Banking Career Readiness Assessment',3,'B','10,000 × 6% = 600 ETB simple interest for one year.'),
('Banking Career Readiness Assessment',4,'A','A balance sheet presents assets, liabilities and equity at a specific date.'),
('Banking Career Readiness Assessment',5,'B','Active listening and fact gathering should come before proposing a resolution.'),
('Banking Career Readiness Assessment',6,'C','Professional service includes clear next steps, documentation and appropriate escalation.'),
('Banking Career Readiness Assessment',7,'A','SUM adds numeric values in a spreadsheet range.'),
('Banking Career Readiness Assessment',8,'A','KYC supports identity verification, customer due diligence and risk management.'),
('Banking Career Readiness Assessment',9,'B','Unusual activity inconsistent with a customer profile is a common AML red flag.'),
('Banking Career Readiness Assessment',10,'C','Suspicious credential requests should be independently verified and reported.'),

('Digital Talent Readiness Assessment',1,'A','CSV is a widely supported tabular text format.'),
('Digital Talent Readiness Assessment',2,'A','Repeated copies of the same record are duplicates.'),
('Digital Talent Readiness Assessment',3,'B','Filtering displays records that meet specified conditions.'),
('Digital Talent Readiness Assessment',4,'A','An algorithm is a defined sequence of steps for solving a problem.'),
('Digital Talent Readiness Assessment',5,'A','Variables provide named storage for values used by a program.'),
('Digital Talent Readiness Assessment',6,'A','Conditional statements choose program flow based on conditions.'),
('Digital Talent Readiness Assessment',7,'B','Systematic debugging reproduces the issue and traces relevant logic and data.'),
('Digital Talent Readiness Assessment',8,'A','Supervised learning uses examples associated with known labels or target values.'),
('Digital Talent Readiness Assessment',9,'A','Testing across groups helps identify unequal performance and potential bias.'),
('Digital Talent Readiness Assessment',10,'C','Strong unique passwords plus MFA reduce account-takeover risk.'),

('Health Career Readiness Assessment',1,'B','Health information should be limited to authorized access for legitimate purposes.'),
('Health Career Readiness Assessment',2,'A','Clear language, listening and checking understanding improve communication.'),
('Health Career Readiness Assessment',3,'B','Hand hygiene is required at appropriate moments around patient care and contamination risk.'),
('Health Career Readiness Assessment',4,'A','PPE selection should match the task, hazard and approved protocol.'),
('Health Career Readiness Assessment',5,'B','Approved patient identifiers reduce wrong-patient errors.'),
('Health Career Readiness Assessment',6,'B','Safety concerns should be escalated through established procedures.'),
('Health Career Readiness Assessment',7,'A','Accurate and timely documentation supports safety, continuity and accountability.'),
('Health Career Readiness Assessment',8,'B','Unknown information should be handled according to approved documentation rules.'),
('Health Career Readiness Assessment',9,'B','Privacy and authorization requirements still apply to family requests.'),
('Health Career Readiness Assessment',10,'A','SOPs support consistent, safe and accountable work.'),

('Agribusiness Readiness Assessment',1,'A','A value chain covers connected activities from inputs and production through delivery to customers.'),
('Agribusiness Readiness Assessment',2,'A','Soil tests provide information that supports more appropriate input decisions.'),
('Agribusiness Readiness Assessment',3,'A','A crop calendar organizes key farm activities and timing.'),
('Agribusiness Readiness Assessment',4,'A','Gross margin is 30,000 − 18,000 = 12,000 ETB.'),
('Agribusiness Readiness Assessment',5,'A','Expense records track farm input and operating costs.'),
('Agribusiness Readiness Assessment',6,'A','Appropriate handling and storage reduce avoidable post-harvest loss.'),
('Agribusiness Readiness Assessment',7,'A','Market decisions should compare net return, cost, payment terms and reliability.'),
('Agribusiness Readiness Assessment',8,'A','Efficient irrigation and soil-moisture management can reduce unnecessary water loss.'),
('Agribusiness Readiness Assessment',9,'A','Consistent grading improves quality communication, pricing and buyer trust.'),
('Agribusiness Readiness Assessment',10,'A','Dependence on one buyer creates customer concentration risk.'),

('Community Impact Readiness Assessment',1,'B','A measurable objective states an observable outcome learners can demonstrate.'),
('Community Impact Readiness Assessment',2,'A','Facilitation supports inclusive participation and learning.'),
('Community Impact Readiness Assessment',3,'A','Inclusive practice removes barriers through appropriate accessible adjustments.'),
('Community Impact Readiness Assessment',4,'A','Formative assessment provides feedback during learning.'),
('Community Impact Readiness Assessment',5,'B','Neutral wording reduces leading respondents toward a preferred answer.'),
('Community Impact Readiness Assessment',6,'A','Informed consent supports voluntary and informed participation.'),
('Community Impact Readiness Assessment',7,'A','Data collectors should follow approved clarification protocols and record accurately.'),
('Community Impact Readiness Assessment',8,'A','Stakeholder mapping identifies relevant groups, interests and influence.'),
('Community Impact Readiness Assessment',9,'A','Safeguarding concerns should be handled through established reporting procedures.'),
('Community Impact Readiness Assessment',10,'A','A completion percentage directly measures participation through the end of an activity.'),

('Technical Career Readiness Assessment',1,'A','Pre-use inspection and approved operating procedures are basic safety practices.'),
('Technical Career Readiness Assessment',2,'A','Energy isolation prevents unexpected startup or hazardous-energy release.'),
('Technical Career Readiness Assessment',3,'A','The acceptable range is 49.5–50.5 mm; 49.6 mm is within tolerance.'),
('Technical Career Readiness Assessment',4,'C','At 1:10 scale, 10 mm on the drawing represents 100 mm actual.'),
('Technical Career Readiness Assessment',5,'A','Approved isolation and verification are critical for de-energized electrical work.'),
('Technical Career Readiness Assessment',6,'A','Preventive maintenance uses planned service to reduce avoidable failure.'),
('Technical Career Readiness Assessment',7,'A','Safe systematic troubleshooting identifies causes without bypassing controls.'),
('Technical Career Readiness Assessment',8,'A','Damaged tools should be removed from use until properly repaired or replaced.'),
('Technical Career Readiness Assessment',9,'A','Organized work areas reduce hazards and improve efficiency.'),
('Technical Career Readiness Assessment',10,'A','Near-miss reporting helps identify hazards before a more serious event.'),

('Creative Talent Readiness Assessment',1,'A','Visual hierarchy communicates relative importance and guides attention.'),
('Creative Talent Readiness Assessment',2,'A','Contrast differentiates elements and improves emphasis and readability.'),
('Creative Talent Readiness Assessment',3,'A','Creative choices should be guided by audience, objective and message.'),
('Creative Talent Readiness Assessment',4,'A','Creators should respect copyright, licensing and permission requirements.'),
('Creative Talent Readiness Assessment',5,'A','Storyboards plan the sequence and composition of scenes before production.'),
('Creative Talent Readiness Assessment',6,'A','Clear audio is essential to comprehensible and professional video content.'),
('Creative Talent Readiness Assessment',7,'A','A content calendar organizes topics, channels and publishing dates.'),
('Creative Talent Readiness Assessment',8,'A','A CTA tells the audience what action to take next.'),
('Creative Talent Readiness Assessment',9,'A','Strong case studies explain context, contribution, process and outcome.'),
('Creative Talent Readiness Assessment',10,'A','Professional iteration clarifies the need and makes intentional revisions.'),

('Operations Readiness Assessment',1,'A','5S supports orderly, clean and standardized workplaces.'),
('Operations Readiness Assessment',2,'A','FIFO means First In, First Out.'),
('Operations Readiness Assessment',3,'A','Cycle counting checks selected inventory regularly for record accuracy.'),
('Operations Readiness Assessment',4,'A','Receiving discrepancies should be documented and handled through the approved process.'),
('Operations Readiness Assessment',5,'A','Root-cause analysis addresses underlying reasons for repeated defects.'),
('Operations Readiness Assessment',6,'A','A bottleneck is a capacity constraint that limits overall flow.'),
('Operations Readiness Assessment',7,'A','Lead time is elapsed time from initiation to completion or delivery.'),
('Operations Readiness Assessment',8,'A','Safety stock provides a buffer against demand or supply uncertainty.'),
('Operations Readiness Assessment',9,'A','Verification against the pick instruction reduces wrong-item and wrong-quantity errors.'),
('Operations Readiness Assessment',10,'A','Delivery planning considers capacity, timing, road conditions, cost and route constraints.')
)
insert into private.assessment_answer_keys(question_id, correct_answer, explanation, updated_at)
select q.id, to_jsonb(k.correct_answer), k.explanation, now()
from keys k
join public.skill_assessments sa on sa.title = k.assessment_title
join public.assessment_questions q on q.assessment_id = sa.id and q.question_order = k.question_order
on conflict (question_id)
do update set correct_answer = excluded.correct_answer,
              explanation = excluded.explanation,
              updated_at = now();
;
