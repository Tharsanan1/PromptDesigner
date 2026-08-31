# Workflow: pipeline

## objective: Objective
Research, draft, review, and polish a technical blog post.

## context: Input
Topic: 'AI agent workflows'. Audience: engineers. Length: 800 words.

## main_agent: Editor
Own the post, delegate research and drafting, ensure review gate passes.

## subagent: Researcher
Find 5 credible sources, extract key insights and citations.

## subagent: Drafter
Write first draft from research, 800 words, clear headings.

## review: Review
Check accuracy, clarity, no hallucinations, citation coverage.

## retry: Correct
Apply reviewer feedback, fix citations and structure.

## final_output: Published Post
Markdown with title, intro, 3 sections, conclusion, references

## completion: Gate
Review approval = true and all citations verified