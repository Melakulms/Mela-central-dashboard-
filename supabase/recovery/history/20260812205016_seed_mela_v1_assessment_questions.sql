-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260812205016
with seed(assessment_title, question_order, competency, difficulty, prompt, choices, correct_answer, explanation) as (
values
-- Banking & Financial Services
('Banking Career Readiness Assessment',1,'Banking foundations',1,'What is one core role of a commercial bank?',
 '[{"id":"A","text":"Only printing national currency"},{"id":"B","text":"Accepting deposits and providing financial services such as payments and credit"},{"id":"C","text":"Setting all product prices in the economy"},{"id":"D","text":"Issuing university degrees"}]'::jsonb,'B','Commercial banks commonly accept deposits and provide payment, savings and credit services.'),
('Banking Career Readiness Assessment',2,'Banking products',1,'Which account is generally designed for frequent deposits, withdrawals and payments?',
 '[{"id":"A","text":"A transaction/current account"},{"id":"B","text":"A fixed asset register"},{"id":"C","text":"An inventory account"},{"id":"D","text":"A payroll expense ledger"}]'::jsonb,'A','Transaction or current accounts are intended for frequent day-to-day money movement.'),
('Banking Career Readiness Assessment',3,'Financial numeracy',2,'A customer deposits 10,000 ETB at 6% simple annual interest for one year. What is the simple interest before tax or fees?',
 '[{"id":"A","text":"60 ETB"},{"id":"B","text":"600 ETB"},{"id":"C","text":"1,600 ETB"},{"id":"D","text":"6,000 ETB"}]'::jsonb,'B','Simple interest for one year is principal × rate = 10,000 × 0.06 = 600 ETB.'),
('Banking Career Readiness Assessment',4,'Financial statements',2,'Which statement shows assets, liabilities and equity at a point in time?',
 '[{"id":"A","text":"Balance sheet / statement of financial position"},{"id":"B","text":"Marketing plan"},{"id":"C","text":"Attendance register"},{"id":"D","text":"Customer complaint log"}]'::jsonb,'A','A balance sheet presents assets, liabilities and equity at a specific date.'),
('Banking Career Readiness Assessment',5,'Customer service',1,'A customer is upset about an unexplained charge. What should a service employee do first?',
 '[{"id":"A","text":"Interrupt and explain the policy immediately"},{"id":"B","text":"Listen, confirm the concern and gather the relevant account details"},{"id":"C","text":"Promise a refund before checking anything"},{"id":"D","text":"Ask the customer to leave"}]'::jsonb,'B','Active listening and fact gathering should come before proposing a resolution.'),
('Banking Career Readiness Assessment',6,'Professional communication',2,'Which response is the most professional when you cannot solve a customer issue immediately?',
 '[{"id":"A","text":"I do not know; try again later"},{"id":"B","text":"That is not my problem"},{"id":"C","text":"I will explain the next step, record the issue and escalate it to the right team"},{"id":"D","text":"Ignore the request until the customer follows up"}]'::jsonb,'C','Professional service includes clear next steps, documentation and appropriate escalation.'),
('Banking Career Readiness Assessment',7,'Spreadsheet skills',1,'Which spreadsheet function is commonly used to add a range of numbers?',
 '[{"id":"A","text":"SUM"},{"id":"B","text":"LEFT"},{"id":"C","text":"LEN"},{"id":"D","text":"UPPER"}]'::jsonb,'A','SUM is the standard function for adding values in a range.'),
('Banking Career Readiness Assessment',8,'KYC and compliance',2,'What is the main purpose of Know Your Customer (KYC) procedures?',
 '[{"id":"A","text":"To identify customers and understand relevant risk before providing services"},{"id":"B","text":"To choose the customer’s career"},{"id":"C","text":"To advertise only premium products"},{"id":"D","text":"To replace all transaction records"}]'::jsonb,'A','KYC supports identity verification, customer due diligence and risk management.'),
('Banking Career Readiness Assessment',9,'AML awareness',2,'Which situation is most likely to require additional review under anti-money-laundering controls?',
 '[{"id":"A","text":"A routine salary deposit consistent with the customer profile"},{"id":"B","text":"Repeated unusual transactions that do not fit the known customer activity"},{"id":"C","text":"A customer updating a phone number"},{"id":"D","text":"A customer asking for branch opening hours"}]'::jsonb,'B','Unusual activity inconsistent with a customer profile is a common AML red flag requiring review.'),
('Banking Career Readiness Assessment',10,'Cyber hygiene',1,'A message asks an employee to click an urgent link and enter banking credentials. What is the safest action?',
 '[{"id":"A","text":"Click quickly before the link expires"},{"id":"B","text":"Forward the password to a colleague"},{"id":"C","text":"Verify the request through an approved channel and report suspicious phishing"},{"id":"D","text":"Reply with the customer database"}]'::jsonb,'C','Suspicious credential requests should be independently verified and reported through approved security processes.'),

-- Technology
('Digital Talent Readiness Assessment',1,'Digital literacy',1,'Which file format is commonly used for tabular data that can be opened by many spreadsheet and data tools?',
 '[{"id":"A","text":"CSV"},{"id":"B","text":"MP3"},{"id":"C","text":"PNG"},{"id":"D","text":"MP4"}]'::jsonb,'A','CSV is a widely supported text format for rows and columns of data.'),
('Digital Talent Readiness Assessment',2,'Data quality',2,'A dataset contains the same customer record three times. Which data-quality issue is this?',
 '[{"id":"A","text":"Duplication"},{"id":"B","text":"Encryption"},{"id":"C","text":"Compression"},{"id":"D","text":"Visualization"}]'::jsonb,'A','Repeated copies of the same record are duplicates and can distort analysis.'),
('Digital Talent Readiness Assessment',3,'Data analysis',1,'What is the purpose of filtering a dataset?',
 '[{"id":"A","text":"To permanently delete the database"},{"id":"B","text":"To display rows that meet selected conditions"},{"id":"C","text":"To convert every number into text"},{"id":"D","text":"To disable formulas"}]'::jsonb,'B','Filtering narrows visible data to records matching specified conditions.'),
('Digital Talent Readiness Assessment',4,'Computational thinking',2,'What is an algorithm?',
 '[{"id":"A","text":"A step-by-step procedure for solving a problem"},{"id":"B","text":"A type of computer monitor"},{"id":"C","text":"A social-media username"},{"id":"D","text":"A database password"}]'::jsonb,'A','An algorithm is a defined sequence of steps for completing a task or solving a problem.'),
('Digital Talent Readiness Assessment',5,'Programming foundations',1,'In programming, what is a variable primarily used for?',
 '[{"id":"A","text":"Storing a value that code can use or change"},{"id":"B","text":"Physically cooling a computer"},{"id":"C","text":"Replacing the operating system"},{"id":"D","text":"Printing a document automatically"}]'::jsonb,'A','Variables provide named storage for values used by a program.'),
('Digital Talent Readiness Assessment',6,'Programming foundations',2,'Which programming structure chooses between actions based on whether a condition is true or false?',
 '[{"id":"A","text":"Conditional / if statement"},{"id":"B","text":"Image crop"},{"id":"C","text":"File rename"},{"id":"D","text":"Screen brightness"}]'::jsonb,'A','Conditional statements control program flow based on evaluated conditions.'),
('Digital Talent Readiness Assessment',7,'Debugging',2,'Your program gives the wrong output. What is the best first debugging approach?',
 '[{"id":"A","text":"Delete the whole project immediately"},{"id":"B","text":"Reproduce the problem, inspect inputs and trace the relevant logic"},{"id":"C","text":"Change random lines until it works once"},{"id":"D","text":"Hide the error message"}]'::jsonb,'B','Systematic debugging starts by reproducing the issue and tracing the affected logic and data.'),
('Digital Talent Readiness Assessment',8,'AI foundations',2,'In supervised machine learning, what does the training data normally include?',
 '[{"id":"A","text":"Examples paired with known target labels or outcomes"},{"id":"B","text":"Only blank files"},{"id":"C","text":"Only hardware specifications"},{"id":"D","text":"No examples at all"}]'::jsonb,'A','Supervised learning learns from examples associated with known labels or target values.'),
('Digital Talent Readiness Assessment',9,'Responsible AI',2,'Why should an AI system be tested across different user groups?',
 '[{"id":"A","text":"To identify performance gaps and possible unfair bias"},{"id":"B","text":"To guarantee the system never needs monitoring"},{"id":"C","text":"To make the source code longer"},{"id":"D","text":"To remove all documentation"}]'::jsonb,'A','Testing across relevant groups helps detect unequal performance and potential bias.'),
('Digital Talent Readiness Assessment',10,'Cybersecurity',1,'Which account practice gives stronger protection against password theft?',
 '[{"id":"A","text":"Using the same short password everywhere"},{"id":"B","text":"Sharing passwords in group chat"},{"id":"C","text":"Using a strong unique password plus multi-factor authentication"},{"id":"D","text":"Writing the password in a public document"}]'::jsonb,'C','Unique strong passwords combined with MFA reduce the risk of account takeover.'),

-- Health & Clinical Support
('Health Career Readiness Assessment',1,'Confidentiality',1,'A patient record contains private health information. Who should access it?',
 '[{"id":"A","text":"Anyone who is curious"},{"id":"B","text":"Only authorized people who need it for legitimate work"},{"id":"C","text":"All visitors"},{"id":"D","text":"Anyone on social media"}]'::jsonb,'B','Health information should be limited to authorized access for legitimate purposes.'),
('Health Career Readiness Assessment',2,'Patient communication',1,'Which communication approach best supports understanding?',
 '[{"id":"A","text":"Use clear language, listen and confirm the person understood"},{"id":"B","text":"Use unexplained technical jargon only"},{"id":"C","text":"Speak as quickly as possible"},{"id":"D","text":"Avoid questions"}]'::jsonb,'A','Clear language, listening and checking understanding improve patient communication.'),
('Health Career Readiness Assessment',3,'Infection prevention',1,'When should hand hygiene be performed in a healthcare workplace?',
 '[{"id":"A","text":"Only at the end of the month"},{"id":"B","text":"At appropriate moments before and after relevant patient or contamination contact"},{"id":"C","text":"Only when a supervisor is watching"},{"id":"D","text":"Never when gloves are available"}]'::jsonb,'B','Hand hygiene is required at appropriate points around patient care and contamination risk; gloves do not replace it.'),
('Health Career Readiness Assessment',4,'Safety and PPE',2,'How should personal protective equipment (PPE) be selected?',
 '[{"id":"A","text":"Based on the task, exposure risk and workplace protocol"},{"id":"B","text":"Based only on favorite color"},{"id":"C","text":"Use every item for every task regardless of risk"},{"id":"D","text":"Never use PPE"}]'::jsonb,'A','PPE selection should match the specific hazard and approved workplace procedures.'),
('Health Career Readiness Assessment',5,'Patient identification',2,'Before a procedure or specimen collection, what is a safer identification practice?',
 '[{"id":"A","text":"Rely only on room number"},{"id":"B","text":"Use approved patient identifiers according to facility protocol"},{"id":"C","text":"Guess based on appearance"},{"id":"D","text":"Ask another patient"}]'::jsonb,'B','Approved identifiers help prevent wrong-patient errors; room number alone is not sufficient.'),
('Health Career Readiness Assessment',6,'Incident escalation',2,'You notice a safety issue outside your authority to fix. What should you do?',
 '[{"id":"A","text":"Hide it"},{"id":"B","text":"Follow the facility escalation and incident-reporting process promptly"},{"id":"C","text":"Post it publicly before reporting internally"},{"id":"D","text":"Assume someone else will handle it"}]'::jsonb,'B','Safety concerns should be escalated through established procedures without delay.'),
('Health Career Readiness Assessment',7,'Health records',1,'Which is the best documentation practice?',
 '[{"id":"A","text":"Record accurate, timely and relevant information using approved systems"},{"id":"B","text":"Invent missing information"},{"id":"C","text":"Use another person’s login"},{"id":"D","text":"Delete inconvenient entries"}]'::jsonb,'A','Accurate and timely documentation supports continuity, safety and accountability.'),
('Health Career Readiness Assessment',8,'Data quality',2,'A form requires a date, but the date is unknown. What is the safest approach?',
 '[{"id":"A","text":"Make up a date"},{"id":"B","text":"Follow the approved process for unknown or missing information"},{"id":"C","text":"Copy a date from another patient"},{"id":"D","text":"Change the form template without approval"}]'::jsonb,'B','Unknown data should be handled according to approved documentation rules rather than fabricated.'),
('Health Career Readiness Assessment',9,'Professional conduct',2,'A family member asks you for confidential information that you are not authorized to release. What should you do?',
 '[{"id":"A","text":"Provide it because they asked politely"},{"id":"B","text":"Follow privacy rules and refer the request through the authorized process"},{"id":"C","text":"Send the full record by personal email"},{"id":"D","text":"Discuss it in a public area"}]'::jsonb,'B','Privacy and authorization requirements still apply to family requests.'),
('Health Career Readiness Assessment',10,'Workplace safety',1,'Why are standard operating procedures important in clinical support work?',
 '[{"id":"A","text":"They promote consistent, safe and accountable work"},{"id":"B","text":"They eliminate the need for training"},{"id":"C","text":"They allow anyone to ignore supervision"},{"id":"D","text":"They are only for decoration"}]'::jsonb,'A','SOPs help teams perform tasks consistently according to approved safety and quality expectations.'),

-- Agriculture & Agribusiness
('Agribusiness Readiness Assessment',1,'Agribusiness foundations',1,'What does an agricultural value chain describe?',
 '[{"id":"A","text":"The activities that move a product from inputs and production through processing, distribution and customers"},{"id":"B","text":"Only the weather forecast"},{"id":"C","text":"Only farm ownership documents"},{"id":"D","text":"Only tractor maintenance"}]'::jsonb,'A','A value chain covers the connected activities that create and deliver agricultural products.'),
('Agribusiness Readiness Assessment',2,'Soil and crop management',1,'Why is soil testing useful before deciding on fertilizer or soil amendments?',
 '[{"id":"A","text":"It helps identify soil conditions and supports better input decisions"},{"id":"B","text":"It guarantees rainfall"},{"id":"C","text":"It replaces all field observation"},{"id":"D","text":"It determines market prices"}]'::jsonb,'A','Soil tests provide information that can guide more appropriate soil and nutrient management decisions.'),
('Agribusiness Readiness Assessment',3,'Farm planning',2,'What is the main purpose of a crop calendar?',
 '[{"id":"A","text":"To plan key farm activities and timing across the production cycle"},{"id":"B","text":"To replace financial records"},{"id":"C","text":"To predict exact prices one year ahead"},{"id":"D","text":"To record employee birthdays only"}]'::jsonb,'A','Crop calendars help organize land preparation, planting, management and harvest timing.'),
('Agribusiness Readiness Assessment',4,'Farm finance',2,'A farmer sells produce for 30,000 ETB and has variable production costs of 18,000 ETB. What is the gross margin before fixed costs?',
 '[{"id":"A","text":"12,000 ETB"},{"id":"B","text":"18,000 ETB"},{"id":"C","text":"30,000 ETB"},{"id":"D","text":"48,000 ETB"}]'::jsonb,'A','Gross margin is revenue minus variable costs: 30,000 − 18,000 = 12,000 ETB.'),
('Agribusiness Readiness Assessment',5,'Recordkeeping',1,'Which record is most useful for knowing how much was spent on seed, fertilizer and hired labor?',
 '[{"id":"A","text":"Farm expense record"},{"id":"B","text":"Weather photo album"},{"id":"C","text":"Personal contact list"},{"id":"D","text":"Social media comments"}]'::jsonb,'A','Expense records allow a farm business to track input and operating costs.'),
('Agribusiness Readiness Assessment',6,'Post-harvest management',2,'Which practice can help reduce post-harvest losses?',
 '[{"id":"A","text":"Appropriate handling, drying/storage and protection from contamination or pests"},{"id":"B","text":"Mix damaged and good produce without inspection"},{"id":"C","text":"Leave produce exposed to avoidable moisture"},{"id":"D","text":"Ignore storage conditions"}]'::jsonb,'A','Good handling and storage practices help protect quality and reduce avoidable loss.'),
('Agribusiness Readiness Assessment',7,'Market analysis',2,'Two buyers offer different prices, transport costs and payment terms. What should a producer compare?',
 '[{"id":"A","text":"The net return and reliability of each offer, not price alone"},{"id":"B","text":"Only the buyer’s logo"},{"id":"C","text":"Only the highest headline price"},{"id":"D","text":"Only distance without considering costs"}]'::jsonb,'A','A sound market decision considers net revenue, costs, payment terms and buyer reliability.'),
('Agribusiness Readiness Assessment',8,'Sustainable agriculture',1,'Which is an example of a water-conservation practice?',
 '[{"id":"A","text":"Reducing unnecessary water loss through suitable irrigation and soil-moisture management"},{"id":"B","text":"Leaving irrigation running when not needed"},{"id":"C","text":"Removing all ground cover in every situation"},{"id":"D","text":"Ignoring leaks"}]'::jsonb,'A','Efficient irrigation and soil-moisture management can reduce unnecessary water losses.'),
('Agribusiness Readiness Assessment',9,'Quality management',2,'Why should produce be graded or sorted consistently before sale?',
 '[{"id":"A","text":"To create clearer quality categories and support reliable buyer expectations"},{"id":"B","text":"To hide damaged items"},{"id":"C","text":"To avoid recording quantities"},{"id":"D","text":"To make every product identical"}]'::jsonb,'A','Consistent grading supports quality communication, pricing and buyer trust.'),
('Agribusiness Readiness Assessment',10,'Risk management',2,'A farm depends on one buyer for all sales. What business risk does this create?',
 '[{"id":"A","text":"Customer concentration risk"},{"id":"B","text":"No risk at all"},{"id":"C","text":"Only weather risk"},{"id":"D","text":"Only equipment depreciation"}]'::jsonb,'A','Dependence on one buyer increases exposure if that buyer changes terms or stops purchasing.'),

-- Education & Community Development
('Community Impact Readiness Assessment',1,'Learning design',1,'Which learning objective is the most measurable?',
 '[{"id":"A","text":"Understand everything about communication"},{"id":"B","text":"By the end, participants can list three elements of active listening"},{"id":"C","text":"Enjoy the workshop"},{"id":"D","text":"Know many things"}]'::jsonb,'B','A measurable objective states an observable outcome learners can demonstrate.'),
('Community Impact Readiness Assessment',2,'Facilitation',1,'What is a facilitator’s primary role in a participatory discussion?',
 '[{"id":"A","text":"Support an inclusive process that helps the group engage with the topic"},{"id":"B","text":"Speak for the entire session without interaction"},{"id":"C","text":"Choose answers for participants"},{"id":"D","text":"Prevent all questions"}]'::jsonb,'A','Facilitation guides process, participation and learning rather than dominating the group.'),
('Community Impact Readiness Assessment',3,'Inclusive education',2,'A participant has difficulty reading small text. What is an inclusive response?',
 '[{"id":"A","text":"Offer an accessible format or adjustment without embarrassing the participant"},{"id":"B","text":"Exclude them from the activity"},{"id":"C","text":"Tell them to copy another person"},{"id":"D","text":"Ignore the barrier"}]'::jsonb,'A','Inclusive practice identifies barriers and provides reasonable ways for people to participate.'),
('Community Impact Readiness Assessment',4,'Assessment for learning',2,'What is formative assessment used for?',
 '[{"id":"A","text":"Checking learning during the process so teaching or support can be adjusted"},{"id":"B","text":"Only issuing a final certificate"},{"id":"C","text":"Replacing all instruction"},{"id":"D","text":"Collecting unrelated personal information"}]'::jsonb,'A','Formative assessment provides feedback during learning rather than only at the end.'),
('Community Impact Readiness Assessment',5,'Research basics',2,'Which survey question is least biased?',
 '[{"id":"A","text":"How excellent was our perfect program?"},{"id":"B","text":"How would you rate the program overall?"},{"id":"C","text":"You agree the program was useful, right?"},{"id":"D","text":"Why did everyone love the program?"}]'::jsonb,'B','Neutral wording reduces leading respondents toward a preferred answer.'),
('Community Impact Readiness Assessment',6,'Research ethics',2,'Why is informed consent important when collecting information from participants?',
 '[{"id":"A","text":"People should understand the purpose, relevant risks and their choice to participate"},{"id":"B","text":"It guarantees every answer is correct"},{"id":"C","text":"It removes the need for confidentiality"},{"id":"D","text":"It allows data to be used for any purpose without limits"}]'::jsonb,'A','Informed consent supports voluntary and informed participation.'),
('Community Impact Readiness Assessment',7,'Data collection',1,'What should an enumerator do if a required answer is unclear?',
 '[{"id":"A","text":"Use the approved clarification procedure and record the response accurately"},{"id":"B","text":"Invent the answer"},{"id":"C","text":"Copy another participant’s answer"},{"id":"D","text":"Change the questionnaire silently"}]'::jsonb,'A','Data collectors should follow approved protocols rather than fabricate or alter responses.'),
('Community Impact Readiness Assessment',8,'Stakeholder engagement',2,'What is stakeholder mapping used for?',
 '[{"id":"A","text":"Identifying relevant people or groups, their interests and influence"},{"id":"B","text":"Replacing the project budget"},{"id":"C","text":"Selecting only people who agree with the project"},{"id":"D","text":"Avoiding community consultation"}]'::jsonb,'A','Stakeholder mapping helps teams plan engagement based on who is affected or influential.'),
('Community Impact Readiness Assessment',9,'Safeguarding',2,'A participant reports a safeguarding concern. What should a staff member do?',
 '[{"id":"A","text":"Follow the organization’s safeguarding and reporting procedure promptly"},{"id":"B","text":"Promise secrecy regardless of policy"},{"id":"C","text":"Post the details publicly"},{"id":"D","text":"Investigate alone outside their role"}]'::jsonb,'A','Safeguarding concerns should be handled through established reporting and protection procedures.'),
('Community Impact Readiness Assessment',10,'Monitoring and feedback',2,'Which indicator is most useful for tracking workshop completion?',
 '[{"id":"A","text":"Percentage of registered participants who completed the workshop"},{"id":"B","text":"Color of the training room"},{"id":"C","text":"Number of clouds that day"},{"id":"D","text":"Facilitator shoe size"}]'::jsonb,'A','A completion rate directly measures participation through the end of the activity.'),

-- Skilled Trades
('Technical Career Readiness Assessment',1,'Workplace safety',1,'Before using a power tool, what should a worker do?',
 '[{"id":"A","text":"Inspect the tool and guards and follow the approved operating procedure"},{"id":"B","text":"Remove the guard to work faster"},{"id":"C","text":"Use damaged cables if the tool still runs"},{"id":"D","text":"Skip PPE requirements"}]'::jsonb,'A','Pre-use inspection and following the approved procedure are basic safety practices.'),
('Technical Career Readiness Assessment',2,'Energy isolation',2,'What is the purpose of lockout/tagout or an equivalent energy-isolation procedure?',
 '[{"id":"A","text":"Prevent unexpected energization or release of hazardous energy during work"},{"id":"B","text":"Increase machine speed"},{"id":"C","text":"Track employee attendance"},{"id":"D","text":"Replace preventive maintenance"}]'::jsonb,'A','Energy isolation protects workers from unexpected startup or hazardous-energy release.'),
('Technical Career Readiness Assessment',3,'Measurement',2,'A drawing specifies 50.0 mm ± 0.5 mm. Which measurement is within tolerance?',
 '[{"id":"A","text":"49.6 mm"},{"id":"B","text":"49.0 mm"},{"id":"C","text":"50.8 mm"},{"id":"D","text":"51.0 mm"}]'::jsonb,'A','The acceptable range is 49.5 to 50.5 mm; 49.6 mm is within it.'),
('Technical Career Readiness Assessment',4,'Technical drawing',2,'On a drawing with a 1:10 scale, 10 mm on the drawing represents how much on the actual object?',
 '[{"id":"A","text":"1 mm"},{"id":"B","text":"10 mm"},{"id":"C","text":"100 mm"},{"id":"D","text":"1,000 mm"}]'::jsonb,'C','At 1:10, each drawing unit represents ten actual units; 10 mm represents 100 mm.'),
('Technical Career Readiness Assessment',5,'Electrical safety',1,'What should be done before working on an electrical circuit when the task requires de-energization?',
 '[{"id":"A","text":"Follow the approved isolation process and verify the safe condition before work"},{"id":"B","text":"Touch the conductor to see if it is live"},{"id":"C","text":"Assume the switch label is always correct"},{"id":"D","text":"Work faster to reduce exposure"}]'::jsonb,'A','Approved isolation and verification are critical controls for de-energized electrical work.'),
('Technical Career Readiness Assessment',6,'Preventive maintenance',1,'What is preventive maintenance?',
 '[{"id":"A","text":"Planned maintenance intended to reduce failures and keep equipment reliable"},{"id":"B","text":"Repairing equipment only after every breakdown"},{"id":"C","text":"Ignoring manufacturer guidance"},{"id":"D","text":"Replacing all equipment each month"}]'::jsonb,'A','Preventive maintenance uses planned inspection/service to reduce avoidable failure.'),
('Technical Career Readiness Assessment',7,'Troubleshooting',2,'A machine stops unexpectedly. What is a good troubleshooting sequence?',
 '[{"id":"A","text":"Make the area safe, gather symptoms, check likely causes systematically and verify the fix"},{"id":"B","text":"Replace random parts immediately"},{"id":"C","text":"Bypass safety controls"},{"id":"D","text":"Restart repeatedly without inspection"}]'::jsonb,'A','Safe, systematic troubleshooting reduces risk and helps identify the actual cause.'),
('Technical Career Readiness Assessment',8,'Tool care',1,'A hand tool has a cracked handle. What should you do?',
 '[{"id":"A","text":"Remove it from service and follow the repair/replacement process"},{"id":"B","text":"Wrap it loosely and keep using it"},{"id":"C","text":"Give it to a new worker"},{"id":"D","text":"Hide the damage"}]'::jsonb,'A','Damaged tools should be removed from use until properly repaired or replaced.'),
('Technical Career Readiness Assessment',9,'Workplace organization',2,'What is a main benefit of good housekeeping and organized work areas?',
 '[{"id":"A","text":"Reduced hazards and easier, more efficient work"},{"id":"B","text":"More hidden defects"},{"id":"C","text":"Less need to identify tools"},{"id":"D","text":"Permission to block emergency access"}]'::jsonb,'A','Orderly work areas reduce trip, access and tool-management risks and improve efficiency.'),
('Technical Career Readiness Assessment',10,'Incident reporting',2,'A near miss occurs but nobody is injured. Why should it still be reported according to workplace procedure?',
 '[{"id":"A","text":"It can reveal hazards before a more serious event occurs"},{"id":"B","text":"Near misses never contain useful information"},{"id":"C","text":"Only injuries matter"},{"id":"D","text":"Reporting is only for payroll"}]'::jsonb,'A','Near-miss reporting supports hazard identification and prevention.'),

-- Creative & Media
('Creative Talent Readiness Assessment',1,'Visual design',1,'What does visual hierarchy help a viewer understand?',
 '[{"id":"A","text":"Which information should attract attention first, second and later"},{"id":"B","text":"The computer’s battery percentage"},{"id":"C","text":"Only the file size"},{"id":"D","text":"The designer’s password"}]'::jsonb,'A','Visual hierarchy guides attention and communicates relative importance.'),
('Creative Talent Readiness Assessment',2,'Visual design',1,'Why is contrast useful in design?',
 '[{"id":"A","text":"It can separate elements and improve emphasis and readability"},{"id":"B","text":"It guarantees every color is identical"},{"id":"C","text":"It removes the need for layout"},{"id":"D","text":"It makes text intentionally unreadable"}]'::jsonb,'A','Contrast differentiates elements and can improve legibility and emphasis.'),
('Creative Talent Readiness Assessment',3,'Audience strategy',2,'Before creating a campaign graphic, what should you clarify first?',
 '[{"id":"A","text":"The target audience, communication goal and required message"},{"id":"B","text":"Only the designer’s favorite font"},{"id":"C","text":"How many effects can be added"},{"id":"D","text":"Whether the file name is long"}]'::jsonb,'A','Creative choices should be guided by audience, objective and message.'),
('Creative Talent Readiness Assessment',4,'Copyright and ethics',2,'Which is the safest way to use a photograph you did not create?',
 '[{"id":"A","text":"Use it only when you have appropriate permission, license or a valid permitted use"},{"id":"B","text":"Assume anything online is free to reuse commercially"},{"id":"C","text":"Remove the creator’s name and claim it as yours"},{"id":"D","text":"Ignore license terms"}]'::jsonb,'A','Creators should respect copyright, licensing and permission requirements.'),
('Creative Talent Readiness Assessment',5,'Video planning',1,'What is a storyboard used for?',
 '[{"id":"A","text":"Planning the sequence of shots or scenes before production"},{"id":"B","text":"Measuring internet speed"},{"id":"C","text":"Replacing all audio"},{"id":"D","text":"Calculating payroll"}]'::jsonb,'A','Storyboards visualize the planned sequence and composition of a video or animation.'),
('Creative Talent Readiness Assessment',6,'Video production',2,'Why should a creator pay attention to clean audio as well as image quality?',
 '[{"id":"A","text":"Poor audio can make otherwise good content difficult to understand or trust"},{"id":"B","text":"Audio never affects communication"},{"id":"C","text":"Viewers cannot notice sound quality"},{"id":"D","text":"Only subtitles matter in every context"}]'::jsonb,'A','Clear audio is a major part of comprehensible and professional video content.'),
('Creative Talent Readiness Assessment',7,'Content planning',1,'What is a content calendar useful for?',
 '[{"id":"A","text":"Planning topics, channels and publishing dates"},{"id":"B","text":"Storing passwords"},{"id":"C","text":"Replacing audience research"},{"id":"D","text":"Editing photographs automatically"}]'::jsonb,'A','A content calendar helps organize what will be published, where and when.'),
('Creative Talent Readiness Assessment',8,'Digital marketing',2,'What is a call to action (CTA)?',
 '[{"id":"A","text":"A clear prompt telling the audience what action to take next"},{"id":"B","text":"A hidden copyright notice"},{"id":"C","text":"A camera lens specification"},{"id":"D","text":"A spreadsheet formula"}]'::jsonb,'A','A CTA directs the audience toward a desired next step such as applying, registering or learning more.'),
('Creative Talent Readiness Assessment',9,'Portfolio development',2,'What makes a portfolio case study stronger?',
 '[{"id":"A","text":"Showing the problem, your role, process, final work and what you learned or achieved"},{"id":"B","text":"Showing only a file name"},{"id":"C","text":"Hiding your contribution"},{"id":"D","text":"Including unrelated work without explanation"}]'::jsonb,'A','Good case studies explain context, contribution, process and outcome.'),
('Creative Talent Readiness Assessment',10,'Creative feedback',2,'How should a designer respond to constructive client feedback?',
 '[{"id":"A","text":"Clarify the underlying need, evaluate the feedback and revise appropriately"},{"id":"B","text":"Delete the project immediately"},{"id":"C","text":"Refuse to listen to any feedback"},{"id":"D","text":"Change everything without understanding why"}]'::jsonb,'A','Professional iteration uses feedback to understand goals and make intentional revisions.'),

-- Manufacturing & Logistics
('Operations Readiness Assessment',1,'Workplace organization',1,'What is a primary goal of 5S or similar workplace-organization methods?',
 '[{"id":"A","text":"Create an orderly, clean and standardized work area"},{"id":"B","text":"Increase clutter"},{"id":"C","text":"Hide unused materials"},{"id":"D","text":"Remove all labels"}]'::jsonb,'A','5S focuses on organized, clean and standardized workplaces that support safety and efficiency.'),
('Operations Readiness Assessment',2,'Inventory management',1,'What does FIFO mean in inventory handling?',
 '[{"id":"A","text":"First In, First Out"},{"id":"B","text":"Fast Inspection, Fast Output"},{"id":"C","text":"Final Item, Final Order"},{"id":"D","text":"Fixed Inventory, Fixed Operation"}]'::jsonb,'A','FIFO is a stock-rotation principle where earlier received stock is issued before newer stock when appropriate.'),
('Operations Readiness Assessment',3,'Inventory accuracy',2,'What is a cycle count?',
 '[{"id":"A","text":"A scheduled count of a portion of inventory to check record accuracy"},{"id":"B","text":"A bicycle safety inspection"},{"id":"C","text":"A truck route only"},{"id":"D","text":"A payroll calculation"}]'::jsonb,'A','Cycle counting checks selected inventory regularly instead of waiting for a full annual count.'),
('Operations Readiness Assessment',4,'Receiving operations',2,'A delivery quantity does not match the purchase or receiving document. What should happen?',
 '[{"id":"A","text":"Record the discrepancy and follow the receiving exception process"},{"id":"B","text":"Change the document secretly"},{"id":"C","text":"Ignore the difference"},{"id":"D","text":"Accept every quantity without checking"}]'::jsonb,'A','Receiving discrepancies should be documented and handled through the approved process.'),
('Operations Readiness Assessment',5,'Quality management',2,'A defect keeps recurring. Which approach is more likely to prevent it long term?',
 '[{"id":"A","text":"Identify and address the root cause, not only the visible symptom"},{"id":"B","text":"Hide defective units"},{"id":"C","text":"Stop recording defects"},{"id":"D","text":"Blame the last person who saw it"}]'::jsonb,'A','Root-cause analysis seeks the underlying reason for repeated problems so corrective action can be effective.'),
('Operations Readiness Assessment',6,'Process improvement',2,'What is a bottleneck in a production or logistics process?',
 '[{"id":"A","text":"A step whose limited capacity constrains overall flow"},{"id":"B","text":"The fastest step in every process"},{"id":"C","text":"A finished-goods label"},{"id":"D","text":"A customer invoice"}]'::jsonb,'A','A bottleneck limits throughput because work accumulates around its capacity constraint.'),
('Operations Readiness Assessment',7,'Supply chain',1,'What is lead time?',
 '[{"id":"A","text":"The elapsed time from initiating an order or process until completion or delivery"},{"id":"B","text":"Only driving speed"},{"id":"C","text":"The number of employees on leave"},{"id":"D","text":"A warehouse aisle number"}]'::jsonb,'A','Lead time measures how long an order or process takes from start to completion/delivery.'),
('Operations Readiness Assessment',8,'Inventory planning',2,'Why might a business hold safety stock?',
 '[{"id":"A","text":"To reduce the risk of stockouts caused by demand or supply uncertainty"},{"id":"B","text":"To guarantee inventory never has a cost"},{"id":"C","text":"To eliminate forecasting"},{"id":"D","text":"To replace all reorder rules"}]'::jsonb,'A','Safety stock provides a buffer against uncertainty, though it must be balanced against inventory cost.'),
('Operations Readiness Assessment',9,'Warehouse operations',2,'Which practice improves order-picking accuracy?',
 '[{"id":"A","text":"Verify the item and quantity against the pick instruction or system"},{"id":"B","text":"Pick from memory without checking"},{"id":"C","text":"Mix labels between products"},{"id":"D","text":"Skip final verification"}]'::jsonb,'A','Verification against the authorized pick instruction reduces wrong-item and wrong-quantity errors.'),
('Operations Readiness Assessment',10,'Logistics planning',2,'When planning deliveries, what should be considered besides distance?',
 '[{"id":"A","text":"Vehicle capacity, delivery windows, road conditions, cost and route constraints"},{"id":"B","text":"Only the driver’s favorite road"},{"id":"C","text":"Only the color of the packages"},{"id":"D","text":"Nothing else"}]'::jsonb,'A','Practical route planning considers capacity, timing, conditions, constraints and cost as well as distance.')
),
upsert_questions as (
  insert into public.assessment_questions(
    assessment_id, question_order, prompt, question_type, choices, points, active,
    competency, difficulty, language_code, version, updated_at
  )
  select sa.id, s.question_order, s.prompt, 'single_choice', s.choices, 1, true,
         s.competency, s.difficulty, 'en', 1, now()
  from seed s
  join public.skill_assessments sa on sa.title = s.assessment_title
  on conflict (assessment_id, question_order)
  do update set prompt=excluded.prompt,
                question_type=excluded.question_type,
                choices=excluded.choices,
                points=excluded.points,
                active=true,
                competency=excluded.competency,
                difficulty=excluded.difficulty,
                language_code='en',
                version=1,
                updated_at=now()
  returning id, assessment_id, question_order
)
insert into private.assessment_answer_keys(question_id, correct_answer, explanation, updated_at)
select q.id, to_jsonb(s.correct_answer), s.explanation, now()
from seed s
join public.skill_assessments sa on sa.title=s.assessment_title
join public.assessment_questions q on q.assessment_id=sa.id and q.question_order=s.question_order
on conflict (question_id)
do update set correct_answer=excluded.correct_answer,
              explanation=excluded.explanation,
              updated_at=now();

update public.skill_assessments
set instructions = 'Complete all 10 questions within 30 minutes. Choose the best answer for each question. Passing score: 75%. This is a proctored Mela Career Passport assessment; a passing score is verified only after the integrity review is clear.',
    question_count = 10,
    duration_minutes = 30,
    pass_score = 75,
    max_attempts = 3,
    is_proctored = true,
    shuffle_questions = true,
    shuffle_choices = true,
    cooldown_hours = 0,
    status = 'published',
    updated_at = now()
where title in (
 'Banking Career Readiness Assessment',
 'Digital Talent Readiness Assessment',
 'Health Career Readiness Assessment',
 'Agribusiness Readiness Assessment',
 'Community Impact Readiness Assessment',
 'Technical Career Readiness Assessment',
 'Creative Talent Readiness Assessment',
 'Operations Readiness Assessment'
);

do $$
declare v_bad integer;
begin
  select count(*) into v_bad
  from (
    select sa.id
    from public.skill_assessments sa
    left join public.assessment_questions q on q.assessment_id=sa.id and q.active=true
    where sa.title in (
      'Banking Career Readiness Assessment','Digital Talent Readiness Assessment','Health Career Readiness Assessment','Agribusiness Readiness Assessment',
      'Community Impact Readiness Assessment','Technical Career Readiness Assessment','Creative Talent Readiness Assessment','Operations Readiness Assessment'
    )
    group by sa.id, sa.question_count
    having count(q.id) < sa.question_count
  ) x;
  if v_bad > 0 then raise exception 'One or more assessments do not have enough questions'; end if;
end $$;
;
