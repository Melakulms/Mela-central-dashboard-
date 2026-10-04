-- Historical recovery only. Do not apply to an existing production database.
-- Original recorded version: 20260809153037
insert into public.course_lessons
(course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'What AI Is',1,'What AI Is: Core Concepts',1,12,true,'# What AI Is: Core Concepts

Artificial intelligence is a broad field focused on building systems that can perform tasks that normally require aspects of human intelligence. Modern AI systems can recognize patterns, generate text and images, classify information, make predictions, recommend actions, and support decisions.

## AI is not one thing

The term AI covers many different techniques. Some systems use hand-written rules. Others learn statistical patterns from data. Machine learning is a major part of modern AI: instead of programming every decision rule directly, developers train a model on examples so it can learn relationships that generalize to new inputs.

Generative AI is a family of systems designed to create new content such as text, images, audio, video, or code. Large language models are generative AI systems trained on very large collections of text and other data. Their core behavior is to predict useful continuations based on the context they receive.

## What a model actually does

A model does not understand the world in the same way a person does. It transforms inputs into numerical representations, applies learned parameters, and produces an output. The output may appear fluent or intelligent because the model has learned complex patterns from large datasets.

This distinction matters because fluent output can still be wrong. A model can produce an answer that sounds confident but contains invented facts, missing context, or outdated information.

## Three practical capabilities

1. **Prediction:** estimating what is likely to happen or what category something belongs to.
2. **Generation:** producing new text, images, code, or other content.
3. **Decision support:** helping people compare options, summarize evidence, or identify patterns.

## Human judgement remains essential

AI is strongest when paired with human goals, context, and verification. People are responsible for deciding what problem should be solved, what data is appropriate, what risks matter, and whether the output is good enough to use.

A useful mental model is: **AI can accelerate thinking and production, but humans remain accountable for decisions and consequences.**

## Example

Imagine a school administrator who receives 500 written survey responses. An AI system can summarize recurring themes and group similar feedback. But the administrator should still inspect examples, verify whether the summary represents minority viewpoints, and decide what actions are appropriate.

## Key takeaway

AI is a tool for pattern recognition, prediction, generation, and decision support. Its value comes from combining model capability with good human judgement, clear goals, appropriate data, and verification.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set module_title=excluded.module_title,title=excluded.title,duration_minutes=excluded.duration_minutes,is_preview=excluded.is_preview,content_text=excluded.content_text;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'What AI Is',1,'What AI Is: Applied Lab',2,18,false,'# Applied Lab: Identify AI in Real Life

Choose three products or services you use regularly. For each one, answer:

- What task is being automated or assisted?
- Is the system predicting, generating, recommending, or classifying?
- What data might it use?
- What could go wrong if its output is incorrect?
- Where should a human remain involved?

Finish by writing a short paragraph explaining which use case creates the most value and which carries the most risk.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'How Generative AI Works',2,'How Generative AI Works: Core Concepts',1,12,false,'# How Generative AI Works

Generative AI learns patterns from training data and uses those patterns to create new outputs. Large language models break text into small units called tokens and learn relationships between those tokens across massive datasets.

When you provide a prompt, the model uses the prompt as context and predicts a sequence of likely tokens. The process repeats until the response is complete. The model is not retrieving a single stored answer; it is generating a response based on learned statistical relationships.

## Important consequences

- The same prompt can produce different outputs.
- Small wording changes can affect results.
- The model can combine ideas in useful ways.
- The model can also invent information because plausible language is not the same as verified truth.

## Context matters

Models perform better when they receive enough relevant context. A vague instruction such as “write a report” forces the model to guess. A better instruction explains the audience, purpose, source material, constraints, and desired format.

## Key takeaway

Generative AI is powerful because it can synthesize and create, but reliability improves when users provide strong context and verify important outputs.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'How Generative AI Works',2,'How Generative AI Works: Applied Lab',2,18,false,'# Applied Lab: Improve Context

Start with this weak prompt: “Help me study.”

Rewrite it to include:
- the subject,
- your current level,
- the exact topic,
- the time available,
- the type of help you want,
- and how the answer should be formatted.

Compare the weak and improved versions. Explain why the second prompt should produce a more useful answer.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Prompting Fundamentals',3,'Prompting Fundamentals: Core Concepts',1,12,false,'# Prompting Fundamentals

A prompt is the instruction and context you provide to an AI system. Strong prompts reduce ambiguity and make it easier to evaluate whether the response is useful.

A practical structure is:

1. **Goal:** what you want accomplished.
2. **Context:** background information the model needs.
3. **Constraints:** limits, rules, or things to avoid.
4. **Output format:** how the answer should be organized.
5. **Quality criteria:** what a good result must include.

## Example

Instead of “write an email,” try:

“Draft a professional 120-word email to a university admissions office asking whether international applicants may submit an updated transcript after the deadline. Keep the tone respectful and concise. Do not invent policy details; clearly phrase any uncertainty as a question.”

## Iteration

Prompting is not a one-shot activity. Review the result, identify what is weak, and give focused feedback. Iteration is often more effective than making the first prompt extremely long.

## Key takeaway

Clear goals, useful context, constraints, output expectations, and iteration are the foundation of reliable prompting.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Prompting Fundamentals',3,'Prompting Fundamentals: Applied Lab',2,18,false,'# Applied Lab: Build a Structured Prompt

Choose a real task from work or study. Create a prompt containing:

- Goal
- Context
- Constraints
- Output format
- Quality criteria

Run the prompt in an AI tool if available. Record one weakness in the first result and write one follow-up instruction that improves it.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Verification and Hallucinations',4,'Verification and Hallucinations: Core Concepts',1,12,false,'# Verification and Hallucinations

AI systems can produce statements that are fluent but incorrect. These errors are often called hallucinations. They may include invented sources, incorrect dates, fabricated statistics, or false explanations.

## Verification strategy

Use a risk-based approach:

- Low-stakes brainstorming may need minimal checking.
- School assignments should verify factual claims and citations.
- Business decisions should verify data, assumptions, and calculations.
- Medical, legal, financial, or safety-critical decisions require authoritative sources and qualified human review.

## Ask for evidence, but verify it yourself

An AI model can provide sources, but it may also invent citations. Open the original source, check whether it actually supports the claim, and confirm that it is current enough for the decision.

## Numerical outputs

Recalculate important arithmetic and inspect spreadsheet formulas. A polished explanation does not prove the numbers are correct.

## Key takeaway

Trust should depend on evidence and risk—not on how confident the AI sounds.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Verification and Hallucinations',4,'Verification and Hallucinations: Applied Lab',2,18,false,'# Applied Lab: Verification Checklist

Take an AI-generated answer containing at least three factual claims. For each claim:

1. Identify what needs verification.
2. Find an independent authoritative source.
3. Mark the claim as supported, unsupported, or uncertain.
4. Correct any inaccurate statement.

Create a five-point verification checklist you can reuse for future AI work.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Responsible AI',5,'Responsible AI: Core Concepts',1,12,false,'# Responsible AI

Responsible AI means using AI in ways that protect people, respect rights, reduce avoidable harm, and keep humans accountable for important decisions.

## Core areas

**Privacy:** Do not paste sensitive personal, financial, health, or confidential company information into tools unless you know the data-handling rules and have permission.

**Bias:** AI systems can reproduce unfair patterns present in training data or system design. Review outputs that affect people for unfair treatment or missing perspectives.

**Transparency:** People should understand when AI materially contributes to important content or decisions when disclosure is relevant.

**Human oversight:** High-impact decisions should not be delegated blindly to an AI system.

**Security:** Treat AI-generated code, links, instructions, and files as untrusted until reviewed.

## Key takeaway

Responsible AI is not a separate step after innovation. It should be part of the workflow from the beginning.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Responsible AI',5,'Responsible AI: Applied Lab',2,18,false,'# Applied Lab: Risk Review

Choose one AI use case such as CV screening, student tutoring, customer support, marketing, or financial analysis.

Create a risk table with four columns:

- Risk
- Who could be affected
- How likely/severe it is
- Mitigation or human-control step

Include at least privacy, bias, accuracy, and misuse risks.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'AI Use-Case Safety Brief',6,'AI Use-Case Safety Brief: Project Guide',1,25,false,'# Capstone: AI Use-Case Safety Brief

Choose a realistic AI use case for Ethiopia, your school, workplace, business, or community.

Your brief should contain:

1. **Problem:** What problem are you trying to solve?
2. **Users:** Who will use or be affected by the system?
3. **AI role:** What will AI do, and what will humans still do?
4. **Benefits:** What measurable value could it create?
5. **Risks:** Accuracy, privacy, bias, security, misuse, and local-context risks.
6. **Controls:** Verification, permissions, escalation, monitoring, and human-review steps.
7. **Success criteria:** How will you know the use case works safely and usefully?

Aim for a clear one-to-two-page document. A strong project demonstrates practical value without ignoring risk.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'AI Use-Case Safety Brief',6,'AI Use-Case Safety Brief: Submission Checklist',2,15,false,'# Capstone Submission Checklist

Before finishing, confirm that your brief:

- defines a specific problem,
- explains who benefits and who may be harmed,
- separates AI responsibilities from human responsibilities,
- includes verification controls,
- considers privacy and bias,
- contains realistic success measures,
- and does not depend on unverified claims.

Revise anything that is vague or impossible to measure.'
from public.courses where slug='ai-fundamentals'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'AI in Everyday Life',1,'AI in Everyday Life: Core Concepts',1,6,true,'# AI in Everyday Life

AI already appears in search, translation, recommendations, navigation, fraud detection, photo tools, customer support, writing assistants, and many workplace systems.

A simple way to recognize AI is to ask whether a system is using data to predict, classify, recommend, generate, or automate a task that normally requires judgement.

AI can save time, but it should not be treated as automatically correct. Good use means knowing the goal, checking important outputs, and protecting sensitive information.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'AI in Everyday Life',1,'AI in Everyday Life: Applied Lab',2,6,false,'# Quick Lab

List five places you encounter AI in daily life. Label each as prediction, classification, recommendation, generation, or automation. Choose one and describe one benefit and one risk.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Prompt Better',2,'Prompt Better: Core Concepts',1,6,false,'# Prompt Better

Useful prompts explain the task, context, constraints, and desired output. Instead of “help with my business,” describe the business, customer, goal, and exact decision you are making.

When the first answer is weak, give focused feedback instead of starting over. Ask the model to correct a specific problem, compare alternatives, or explain assumptions.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Prompt Better',2,'Prompt Better: Applied Lab',2,6,false,'# Quick Lab

Rewrite this prompt: “Write something about AI.”

Add a target audience, purpose, length, tone, three points to cover, and one thing to avoid.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Check Before You Trust',3,'Check Before You Trust: Core Concepts',1,6,false,'# Check Before You Trust

AI-generated answers can be wrong even when they sound confident. Verify important facts using reliable sources, especially dates, statistics, names, citations, calculations, and high-stakes advice.

The higher the consequence of an error, the stronger your verification should be.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Check Before You Trust',3,'Check Before You Trust: Applied Lab',2,6,false,'# Quick Lab

Ask an AI tool a question containing factual information. Identify two claims in the response and verify them independently. Note whether each claim was correct, incomplete, or wrong.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Use AI Safely',4,'Use AI Safely: Core Concepts',1,6,false,'# Use AI Safely

Do not share confidential or sensitive personal information with an AI service unless you understand and accept its data-handling rules. Review AI outputs for bias, harmful assumptions, security problems, and inaccurate information.

Humans should remain responsible for important decisions that affect people, money, health, rights, or safety.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Use AI Safely',4,'Use AI Safely: Applied Lab',2,6,false,'# Quick Lab

Write three examples of information you should not casually paste into a public AI tool. Then write one safe alternative for each example, such as anonymizing data or using a placeholder.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Your First AI Workflow',5,'Your First AI Workflow: Core Concepts',1,6,false,'# Your First AI Workflow

A useful AI workflow has a repeatable sequence:

1. Define the goal.
2. Gather safe, relevant context.
3. Prompt the AI.
4. Review the output.
5. Verify important claims.
6. Improve or edit the result.
7. Save the final process so it can be repeated.

The goal is not just a good answer once. The goal is a reliable way of working.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;

insert into public.course_lessons (course_id,module_title,module_position,title,lesson_position,duration_minutes,is_preview,content_text)
select id,'Your First AI Workflow',5,'Your First AI Workflow: Applied Lab',2,6,false,'# Final Quick Lab

Choose one task you do every week. Write a seven-step AI-assisted workflow for that task. Include where you will verify the AI output and what information you will avoid sharing.'
from public.courses where slug='ai-in-60-minutes'
on conflict (course_id,module_position,lesson_position) do update set content_text=excluded.content_text,is_preview=excluded.is_preview,title=excluded.title,module_title=excluded.module_title,duration_minutes=excluded.duration_minutes;
;
