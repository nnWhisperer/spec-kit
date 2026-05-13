# Phase 1 Quickstart: Verifying Chunked Implementation in /speckit-flow

This quickstart describes how to confirm the feature works end-to-end after Phase 2's tasks land. There is no automated test framework for the orchestrator slash command, so verification is a curated manual walkthrough.

## Prerequisites

- Working tree on branch `001-chunked-implement` with the Phase 2 changes applied:
  - `.claude/commands/speckit-flow.md` edited (Phase 6 rewritten as a loop)
  - `scripts/bash/count-open-tasks.sh` added and executable
  - `.claude/agents/speckit-implement.md` unchanged (the subagent body is upstream-owned; only the orchestrator changes)
- Claude Code CLI installed and configured with the project at `/tmp/spec-kit` (or wherever the fork is checked out).

## Smoke test (single-sitting collapse)

Confirms the loop runs once and terminates immediately when the task list is small.

1. In a scratch directory inside the repo, run `/speckit-specify "Tiny feature: rename one constant in a single file"`.
2. Skip clarification (`/speckit-clarify` → "no critical ambiguities").
3. Run `/speckit-plan`. Tech context can be `bash` for trivially small scope.
4. Run `/speckit-tasks`. Verify the resulting `tasks.md` contains a handful of unchecked tasks.
5. Run `/speckit-flow "(same feature description)"`.
6. **Expected when Phase 6 starts**:
   - Announcement that implementation may take several sittings.
   - Exactly one `Agent(subagent_type=speckit-implement, …)` invocation.
   - No `AskUserQuestion` between sittings.
   - After the single sitting, `tasks.md` shows all tasks `[X]`.
   - No progress note appears (zero gaps between sittings).
   - Orchestrator proceeds to the final summary.

**Pass criteria**: `grep -c '^- \[ \]' specs/<NNN>-tiny-feature/tasks.md` returns `0` and the orchestrator never asked a chunk-size question (SC-001, SC-005).

## Multi-sitting test (the main path)

Confirms the loop actually loops, emits notes, and terminates correctly.

1. Construct (manually) a `specs/999-fake-multi/tasks.md` with ~30 unchecked tasks across multiple Phase headings, contrived so that `speckit-implement` can plausibly do part of the list in one sitting but not all of it.
2. Symlink the required spec/plan stubs alongside so `check-prerequisites.sh` is satisfied.
3. Run `/speckit-flow "(matching description)"`.
4. **Expected**:
   - First Agent invocation runs, marks some tasks `[X]`.
   - Orchestrator reads `tasks.md`, computes `N` done and `M` remaining, emits a one-line progress note.
   - Second Agent invocation fires in the same turn (no `AskUserQuestion`).
   - Loop continues until `count-open-tasks.sh tasks.md` returns `0`.
   - Total invocations match the number of progress notes plus one (K sittings → K-1 notes).
   - Orchestrator stops; no extra prompt appears.

**Pass criteria**: `OPEN_AFTER` reaches 0; the number of progress notes equals `K - 1` where K is the sitting count; no chunk-size question was asked (SC-001, SC-002, SC-004).

## Zero-progress safeguard test

Confirms the orchestrator halts when a sitting makes no progress, rather than retrying.

1. Stage a `tasks.md` whose unchecked tasks point at intentionally impossible operations (e.g., "edit /nonexistent/path"). The implement subagent will fail to make checkbox progress.
2. Run `/speckit-flow`.
3. **Expected**:
   - First Agent invocation runs and returns without checking off any task.
   - Orchestrator's `OPEN_AFTER >= OPEN_BEFORE` check triggers.
   - Orchestrator surfaces the zero-progress condition and halts.
   - **No** second Agent invocation occurs.

**Pass criteria**: Exactly one Agent invocation in Phase 6; the orchestrator's halt message references the zero-progress condition (FR-007, Constitution IV).

## Resume test

Confirms a halted run can be resumed by re-running `/speckit-flow`.

1. From the multi-sitting test, interrupt the run mid-loop (Ctrl+C after the first sitting's progress note).
2. Inspect `tasks.md`: confirm partial completion is preserved (`[X]` only on tasks the first sitting actually finished).
3. Re-run `/speckit-flow "(same description)"`.
4. **Expected**:
   - Orchestrator does not redo completed tasks.
   - The implement subagent on its first re-invoked sitting reads the *current* `tasks.md` and picks up at the first unchecked task.
   - The loop completes the remainder.

**Pass criteria**: Total `[X]` count after resume matches initial total task count; no `[X]` task was reverted; no duplicate work observed in the implementation diff (SC-003).

## What this quickstart does *not* verify

- That `speckit-implement` itself paces sittings well. That is the subagent's responsibility, not the orchestrator's. If the subagent does the whole list in one sitting (favorable case) the multi-sitting test degrades to the smoke test — which is acceptable.
- That the user can interrupt mid-sitting. That is a Claude Code platform behavior, not this feature's.
- Powershell parity for `count-open-tasks.sh`. Out of scope (see research.md, Decision 6).
