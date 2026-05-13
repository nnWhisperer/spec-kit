---
description: Orchestrate the speckit phases end-to-end. Delegates each non-interactive phase to its dedicated subagent for isolated context, and pauses for the user-typed clarify step.
---

# Speckit flow

The user's input is below.

```text
$ARGUMENTS
```

You are orchestrating spec-kit's workflow:

**specify → clarify → plan → tasks → (analyze, optional) → implement**

Non-interactive phases run in isolated subagents via the `Agent` tool with `subagent_type=speckit-<phase>` (loaded from `.claude/agents/speckit-<phase>.md`). The interactive `clarify` phase is **not** a subagent — you invoke it via the `Skill` tool so its body expands inline in this main session, where it has access to the full conversational context (the user's feature description, what `specify` produced, any side discussion) to ask well-informed questions and reply to the user's follow-ups in detail. Disk artifacts under `specs/<NNN-feature>/` are the source of truth — re-check them between phases instead of trusting each subagent's returned message.

## Parsing input

Extract from `$ARGUMENTS`:

- **feature** — the natural-language feature description (required for `specify`)
- **tech** — optional tech-stack/library guidance for `plan` (ask the user when reaching phase 3 if absent)
- **analyze** — whether to run the optional analyze pass (default: ask the user after `tasks`)

If `$ARGUMENTS` is empty, ask the user for the feature description before proceeding.

## Phase 1 — specify

1. Invoke `Agent` with `subagent_type=speckit-specify`. Pass **feature** as the prompt.
2. When it returns, run `bash scripts/bash/check-prerequisites.sh --json --paths-only` and parse the JSON to confirm the spec file exists on disk.
3. If the spec file is missing, **stop** and surface the failure verbatim. Do not auto-retry.

## Phase 2 — clarify (in-session, via Skill tool)

1. Invoke the clarify skill from this main session: `Skill(skill="speckit-clarify")`. Its body expands here, in your context — you have full access to everything that's been said in this conversation, including the feature description and the just-written spec.
2. Follow the clarify skill's instructions inline: ask the user targeted questions via `AskUserQuestion`, answer any follow-up questions they raise (you have the full context to do so in detail), and encode the answers back into the spec file as the skill directs.
3. When the skill body finishes, verify the spec file was updated (e.g., new "Clarifications" section or amended requirements). If the user opted to skip all questions, that's fine — proceed to plan.

Do **not** try to invoke clarify as a subagent. It must run inline to retain context.

## Phase 3 — plan

1. If **tech** was not provided in `$ARGUMENTS`, ask the user for tech-stack/library choices in one short question.
2. Invoke `Agent` with `subagent_type=speckit-plan`. Pass the tech guidance (plus any extra context the user gave) as the prompt.
3. Verify `plan.md` exists next to `spec.md`. Stop on failure.

## Phase 4 — tasks

1. Invoke `Agent` with `subagent_type=speckit-tasks`. The prompt can be terse, e.g. `"Break the plan into dependency-ordered tasks."`
2. Verify `tasks.md` exists. Stop on failure.

## Phase 5 — analyze (optional)

Ask: "Run the analyze pass before implementing? (y/N)". If yes:

1. Invoke `Agent` with `subagent_type=speckit-analyze`.
2. Present its returned summary to the user.
3. Ask whether to address findings now (which means looping back to `plan` or `tasks` — re-invoke that phase's subagent with the corrective context) or proceed to implement.

If no, go straight to phase 6.

## Phase 6 — implement

1. Invoke `Agent` with `subagent_type=speckit-implement`. Prompt: `"Execute tasks.md to completion."`
2. When it returns, run the project's standard build/test command(s) — typically discoverable from `package.json`, `pyproject.toml`, or `Makefile`. Report any failures.
3. Summarise final state to the user: artifacts written, commands run, anything outstanding.

## Operating rules

- **Disk is truth.** Verify artifacts after each phase by reading them, not by parsing the subagent's reply.
- **One try per phase.** If a phase fails, surface the failure; do not auto-retry. The user decides whether to re-run.
- **Do not edit spec/plan/tasks files yourself except inside the clarify skill body.** Subagent phases own their own artifacts; clarify (running inline) is the one exception because it is part of this session.
- **Clarify is the only in-session phase.** All other phases delegate to subagents via `Agent`. Don't pattern-match this exception onto other phases.
- **Pass-through prompts should be terse.** Each phase subagent already has its full instruction body; the invocation prompt is just the user's intent for that phase (treated as `$ARGUMENTS` inside the agent).
