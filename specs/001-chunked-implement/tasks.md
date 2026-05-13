---
description: "Task list for Chunked Implementation in /speckit-flow"
---

# Tasks: Chunked Implementation in /speckit-flow

**Input**: Design documents from `/specs/001-chunked-implement/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md, quickstart.md

**Tests**: Tests are NOT requested by this feature. Verification is manual per `quickstart.md`. No test tasks are generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and review of each story's slice. Note: this feature edits a single file (`.claude/commands/speckit-flow.md`) across stories US1–US3, so tasks within those phases are sequential (no `[P]`) even though they belong to different stories.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

This is a single-project repo with no source tree. Paths used:

- Slash command file: `.claude/commands/speckit-flow.md`
- New bash helper: `scripts/bash/count-open-tasks.sh`
- Specs (this feature): `specs/001-chunked-implement/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Confirm working environment before any edit.

- [X] T001 Verify the working tree is on branch `001-chunked-implement` (`git rev-parse --abbrev-ref HEAD`) and that `.claude/commands/speckit-flow.md`, `scripts/bash/`, and `.specify/memory/constitution.md` all exist. Abort if any check fails.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Create the disk-counting helper that every user story below depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Create `scripts/bash/count-open-tasks.sh` as a single-purpose helper that prints the integer count of lines matching `^- \[ \]` in the file passed as `$1`. Use `set -euo pipefail`. Handle three edge cases explicitly: (a) if `$1` is missing or empty, print a usage line on stderr and exit non-zero; (b) if the file at `$1` does **not** exist, print `0` and exit `0` (this is what FR-009 relies on — a missing `tasks.md` reads as "no open tasks"); (c) if the file exists but `grep` finds zero matches, also print `0` (use `|| true` on the grep). After writing, `chmod +x scripts/bash/count-open-tasks.sh` and smoke-test it against `specs/001-chunked-implement/spec.md` (expected: `0`), a synthetic file with one `- [ ]` line (expected: `1`), and a deliberately non-existent path (expected: `0`).

**Checkpoint**: Foundation ready — user story implementation can now begin.

---

## Phase 3: User Story 1 - Orchestrator loops on the implement subagent until tasks.md is fully done (Priority: P1) 🎯 MVP

**Goal**: Replace Phase 6's single `Agent` call with an orchestrator-driven loop that auto-accepts the implement subagent's per-sitting pacing.

**Independent Test**: Run `/speckit-flow` against a deliberately oversized synthetic `tasks.md` and verify (a) `speckit-implement` is invoked more than once when one sitting cannot finish the list, (b) the user is never asked a chunk-size question, (c) the loop terminates exactly when `count-open-tasks.sh` returns `0`. See `quickstart.md` "Multi-sitting test."

### Implementation for User Story 1

- [X] T003 [US1] In `.claude/commands/speckit-flow.md`, rewrite the **subagent-invocation step** inside "## Phase 6 — implement" (currently step 1 of three: invoke Agent → run build/test → summarise) into the loop scaffold described in `specs/001-chunked-implement/research.md` (Decisions 1 & 2). The two post-loop steps (run build/test, surface the final summary) MUST survive and run **once** after the loop terminates — they are not per-sitting. The loop body: on each iteration, capture `OPEN_BEFORE` by running `bash scripts/bash/count-open-tasks.sh <feature-dir>/tasks.md`, invoke `Agent(subagent_type=speckit-implement)` with the prompt `"Execute tasks.md."` (deliberately weaker than the current `"Execute tasks.md to completion."` — dropping "to completion" lets the subagent self-pace; see research.md Decision 1), capture `OPEN_AFTER` by re-running the helper, and loop while `OPEN_AFTER > 0`. Do **not** pass the subagent any per-sitting scope hint.
- [X] T004 [US1] In the same file, in the "## Operating rules" section, add the rule: "No chunk-size or batch-count question may be forwarded to the user. If the implement subagent surfaces a 'how much should I do?' style suggestion, the orchestrator auto-accepts it; the user is not consulted." Place it next to the existing "specify subagent gets `$ARGUMENTS` verbatim" rule for thematic grouping.
- [X] T005 [US1] In the same file, replace the first paragraph of "## Phase 6 — implement" with a short user-facing announcement that the orchestrator emits before the first sitting: "Implementation may run across several sittings — each one is an isolated `speckit-implement` invocation, which preserves context budget per subagent. The loop ends when `tasks.md` has no remaining unchecked tasks." (FR-003.)

**Checkpoint**: At this point, US1 is functional: a single feature with an oversized `tasks.md` runs to completion across multiple sittings without prompting the user for a chunk size.

---

## Phase 4: User Story 2 - Continuity across sittings (Priority: P1)

**Goal**: Make on-disk state the sole inter-sitting contract. Add the zero-progress safeguard and the empty/done-already guard.

**Independent Test**: Force a sitting to return without completing any task (point one task at an impossible operation) and verify the orchestrator halts cleanly after exactly one Agent invocation — no auto-retry. Also verify that an already-fully-checked `tasks.md` causes Phase 6 to skip the loop entirely. See `quickstart.md` "Zero-progress safeguard test."

### Implementation for User Story 2

- [X] T006 [US2] In `.claude/commands/speckit-flow.md`, inside the Phase 6 loop scaffold introduced in T003, add the zero-progress safeguard described in `research.md` Decision 3: after capturing `OPEN_AFTER`, if `OPEN_AFTER >= OPEN_BEFORE` halt the loop, emit a message to the user explaining no on-disk progress was made in the last sitting, and stop. Do **not** retry the same invocation (Constitution Principle IV).
- [X] T007 [US2] In the same file, immediately after the Phase 6 loop body, add a short explanatory paragraph (1–2 sentences) framing the design: termination and progress are both decided from `tasks.md` on disk; the implement subagent's returned message is a status hint only. Reference Constitution Principle V ("Disk Is Truth"). This documents the invariant for any future maintainer.
- [X] T008 [US2] In the same file, at the top of Phase 6 (before the loop), add the guard: if `count-open-tasks.sh` against the feature's `tasks.md` returns `0` on entry, or if `tasks.md` is missing/empty, skip the loop entirely and tell the user there is nothing to implement. Do not spawn a subagent in this case (FR-009).

**Checkpoint**: US2 is functional. The loop is now driven entirely by disk state, halts safely on zero-progress sittings, and refuses to spawn an empty subagent.

---

## Phase 5: User Story 3 - Visible progress with a stop hatch (Priority: P2)

**Goal**: Add the between-sittings progress note and document the implicit stop hatch. No new questions; the note is informational only.

**Independent Test**: Watch a multi-sitting run and confirm exactly one progress note appears between each pair of sittings, zero notes appear when only one sitting was needed, and no `AskUserQuestion` is invoked anywhere in Phase 6. Interrupt the run between sittings (Ctrl+C) and confirm `tasks.md` reflects only the work the previous sitting actually completed; re-running `/speckit-flow` resumes from the next unchecked task. See `quickstart.md` "Resume test."

### Implementation for User Story 3

- [X] T009 [US3] In `.claude/commands/speckit-flow.md`, inside the Phase 6 loop, between the captured `OPEN_AFTER` check and the next loop iteration, emit a single-line progress note: `Sitting <K> complete: <OPEN_BEFORE - OPEN_AFTER> tasks done this sitting, <OPEN_AFTER> remaining. Continuing…`. `<K>` is a 1-based counter held in the orchestrator's working memory for the turn. Emit the note only when `OPEN_AFTER > 0` (i.e., another sitting will follow).
- [X] T010 [US3] In the same file, in the "## Operating rules" section, add: "No `AskUserQuestion` invocation is permitted inside Phase 6. The user's only halt channel between sittings is interrupting the assistant's turn (Ctrl+C). On the next turn the orchestrator sees the user's stop message and does not re-enter the loop." This codifies `research.md` Decision 5.
- [X] T011 [US3] In the same file, ensure the progress-note logic from T009 is gated on `OPEN_AFTER > 0` so that the terminal sitting (which finishes the list) emits no progress note — the user instead sees the final Phase-6 summary. Cross-check against FR-012 and SC-004.

**Checkpoint**: US3 is functional. Progress notes appear at every gap between sittings, never on the terminal sitting, and the orchestrator never asks the user a question during Phase 6.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Manual verification of the feature against `quickstart.md`. No additional source edits expected; if any scenario fails, loop back to the appropriate user story phase and fix.

- [ ] T012 Run the `quickstart.md` "Smoke test (single-sitting collapse)" end-to-end against a tiny synthetic feature. Verify: zero chunk-size questions, exactly one Agent invocation in Phase 6, zero progress notes, all tasks `[X]` in resulting `tasks.md`. Records SC-001 + SC-005 pass.
- [ ] T013 Run the `quickstart.md` "Multi-sitting test" with a contrived ~30-task `specs/999-fake-multi/tasks.md`. Verify: multiple Agent invocations, K−1 progress notes for K sittings, loop terminates when `count-open-tasks.sh` returns `0`, no chunk-size question asked. Records SC-001 + SC-002 + SC-004 pass.
- [ ] T014 Run the `quickstart.md` "Zero-progress safeguard test" by pointing a task at an impossible operation. Verify: exactly one Agent invocation, orchestrator halts with the zero-progress message, no auto-retry. Records FR-007 + Constitution IV adherence.
- [ ] T015 Run the `quickstart.md` "Resume test": interrupt mid-loop, re-invoke `/speckit-flow`, verify resumed run picks up at the first unchecked task (no redo, no skip). Records SC-003 pass.

---

## Dependencies

Story-level completion order: **Setup → Foundational → US1 → US2 → US3 → Polish**.

Within the implementation phases (US1, US2, US3), tasks are strictly sequential because they edit the same file (`.claude/commands/speckit-flow.md`). The intended apply order is T003 → T004 → T005 → T006 → T007 → T008 → T009 → T010 → T011. A subagent reading this list can safely merge all edits into a single file rewrite in one sitting; the user-story grouping is for review and traceability, not for forcing separate commits.

Foundational task T002 (the helper script) must complete before T003, since T003's loop scaffold invokes the script.

Polish tasks T012–T015 must run after T011 (all user stories done). They are themselves independent walkthroughs but share the same git working tree, so a human typically runs them serially; not marked `[P]`.

## Parallel Opportunities

- **Within this feature**: minimal. The implementation work concentrates in one file, so the only natural parallelism is between Phase 2's helper script creation and a Phase 6 documentation walkthrough — too small to bother marking.
- **Across features**: not applicable; this is a single-feature plan.

## Implementation Strategy

**MVP scope**: User Story 1 (the loop itself). Shipping just US1 already delivers the headline value — the user is no longer asked the chunk-size question, and `/speckit-flow` completes oversized task lists across multiple sittings. US2 hardens correctness (zero-progress safeguard, empty-tasks-md guard); US3 adds the progress-note visibility layer.

Recommended commit sequence for the implementer:

1. After T002: one commit, `feat(scripts): add count-open-tasks.sh helper`.
2. After T003–T011 (single coherent edit to `speckit-flow.md`): one commit, `feat(flow): loop Phase 6 over speckit-implement until tasks.md drains`.
3. After T012–T015 (no source changes, just verification): no commit; if any scenario fails, the fix and its commit happen in whichever earlier phase is responsible.

This keeps the source-of-truth history clean (two implementation commits) without forcing artificial per-story commits that would split a single coherent file rewrite.

## Format validation

All tasks above conform to `- [ ] <ID> [P?] [Story?] <description with file paths>`. Setup, Foundational, and Polish phase tasks intentionally omit `[Story]` labels per the template's rules. No tasks are marked `[P]` because the implementation is single-file.
