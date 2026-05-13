# Implementation Plan: Chunked Implementation in /speckit-flow

**Branch**: `001-chunked-implement` | **Date**: 2026-05-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-chunked-implement/spec.md`

## Summary

`/speckit-flow`'s Phase 6 currently invokes `speckit-implement` exactly once. When the task list is too large to finish in a single subagent context, the subagent's natural "how much should I do this sitting?" pacing surfaces back to the user — turning the user into a chunking dispatcher.

This change moves the loop into the orchestrator. Phase 6 becomes: invoke `speckit-implement`, re-read `tasks.md` from disk, decide based on remaining unchecked tasks whether to invoke again. The subagent owns *what* each sitting does; the orchestrator owns *whether to keep going*. Between sittings the orchestrator emits a one-line progress note and auto-continues; the user can halt by interrupting the turn.

Technically this is a localized rewrite of one section of `.claude/commands/speckit-flow.md` plus a small bash helper to count unchecked tasks. No new files in `.claude/agents/`, no generator changes, no constitution changes.

## Technical Context

**Language/Version**: Markdown (slash command body) + Bash 5 (existing scripts; one new helper)
**Primary Dependencies**: Claude Code's `Agent`, `Read`, `Bash` tools. No external libraries.
**Storage**: Plain files. `specs/<feature>/tasks.md` is the only state read between sittings (markdown checkboxes `- [ ]` / `- [X]`).
**Testing**: Manual end-to-end via `/speckit-flow` invocation on a synthetic feature with a deliberately oversized task list. No automated test framework in this repo.
**Target Platform**: Claude Code CLI (any OS where the existing bash scripts already run)
**Project Type**: Agentic workflow definitions (Markdown + Bash). Single project, no source tree.
**Performance Goals**: Each subagent sitting must fit its own context budget — that *is* the goal. The orchestrator itself is cheap (one Agent call + one Bash read per sitting).
**Constraints**: Constitution Principle I (subagent phase isolation), IV (orchestrator delegates, never edits), V (disk is truth). The loop must derive termination from disk re-reads, not from the subagent's return message.
**Scale/Scope**: One file edited (`.claude/commands/speckit-flow.md`), one helper added (`scripts/bash/count-open-tasks.sh`). ~40-line net change.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Justification |
|-----------|---------|---------------|
| I. Subagent Phase Isolation (NON-NEGOTIABLE) | ✅ Pass | Every sitting is a fresh `speckit-implement` Agent invocation. Sittings share no conversational state — only the on-disk `tasks.md` and the project files. |
| II. Verbatim Body, Rewritten Frontmatter | ✅ Pass (n/a) | Touches `.claude/commands/speckit-flow.md` (the orchestrator, hand-authored) and a new generator-adjacent bash script. Does **not** touch any generated `.claude/agents/speckit-*.md` file. |
| III. Interactive Phases Run In-Session | ✅ Pass (n/a) | `speckit-implement` is non-interactive. No change to the in-session set. The new "progress note" is an emitted text message, not a question — does not turn implement into an interactive phase. |
| IV. Orchestrator Delegates, Never Edits | ✅ Pass | Orchestrator only (a) invokes Agent, (b) reads `tasks.md`, (c) emits a progress note. It never edits `tasks.md` or any phase artifact. The subagent remains the sole author of progress checkboxes. |
| V. Disk Is Truth | ✅ Pass — and reinforced. | Loop termination is decided solely by re-reading `tasks.md`. The subagent's returned message is used as a status hint only. A zero-progress safeguard compares unchecked counts before vs. after to detect "subagent gave up" without trusting the return message. |

**All gates pass. No Complexity Tracking entries required.** Constitution version 1.1.1 referenced.

**Post-Phase-1 re-check (2026-05-13)**: Phase 0 research and Phase 1 artifacts surfaced no design choice that weakens any gate. Decision 1 (no per-sitting prompt to the subagent) actively reinforces Principle II by refusing to wrap the upstream-owned implement body. Decision 2 (grep-based termination) is the literal implementation of Principle V. No re-evaluation needed.

## Project Structure

### Documentation (this feature)

```text
specs/001-chunked-implement/
├── plan.md              # This file (/speckit-plan command output)
├── spec.md              # Feature specification (already exists)
├── research.md          # Phase 0 output (/speckit-plan command)
├── data-model.md        # Phase 1 output (/speckit-plan command) — minimal, see Phase 1
├── quickstart.md        # Phase 1 output (/speckit-plan command)
├── checklists/
│   └── requirements.md  # Spec quality checklist (already exists)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created here)
```

No `contracts/` directory: this feature exposes no external interface. The only contract is the existing `tasks.md` checkbox convention (`- [ ]` open, `- [X]` done), which this feature consumes but does not define.

### Source Code (repository root)

```text
.claude/
└── commands/
    └── speckit-flow.md        # Edited: Phase 6 section rewritten as a loop

scripts/
└── bash/
    └── count-open-tasks.sh    # New: prints integer count of `- [ ]` lines in a given tasks.md

.specify/memory/constitution.md  # Unchanged
templates/commands/implement.md  # Unchanged (upstream-owned)
```

**Structure Decision**: Single-file rewrite of an existing slash command plus one tiny helper script. No new directories, no module boundaries, no test scaffolding (no test framework exists for this repo's Markdown-driven workflows; verification is manual end-to-end per Phase 1's quickstart).

## Complexity Tracking

*Not applicable.* All Constitution Check gates pass without justification needed.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| — | — | — |
