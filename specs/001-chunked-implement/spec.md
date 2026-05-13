# Feature Specification: Chunked Implementation in /speckit-flow

**Feature Branch**: `001-chunked-implement`
**Created**: 2026-05-13
**Status**: Draft
**Input**: User description: "During speckit-implementation step, it is often asked how much of the tasks is to be completed in a single sitting. When we run speckit-flow, it surfaces that question, but it must instead be prompted that the flow can decide to run speckit-implement step in several sittings, so that each agent tacking the implementation can have sufficient context efficiency to tackle smaller set of problems"

## Clarifications

### Session 2026-05-13

- Q: How should the orchestrator decide the boundary of each implementation sitting (the chunking unit)? → A: It does not decide. The `speckit-implement` subagent already surfaces its own per-sitting suggestion (how much it intends to take on this run). The orchestrator accepts that suggestion, lets the sitting run, then re-invokes the subagent. The loop repeats until no tasks remain in `tasks.md`. The orchestrator never partitions `tasks.md` itself.
- Q: Is the user gated between sittings, or is the loop fully autonomous? → A: Auto-continue with stop hatch. Between sittings the orchestrator emits a brief progress note (completed-this-sitting / remaining counts) and auto-continues into the next sitting. The user can interject "stop" to halt the loop; otherwise no per-sitting confirmation is required. Default is to keep going.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Orchestrator loops on the implement subagent until tasks.md is fully done (Priority: P1)

When the user runs `/speckit-flow` and the workflow reaches the implementation phase, the orchestrator invokes `speckit-implement` once, accepts whatever per-sitting suggestion that subagent surfaces (e.g., "I'll take the next P1 group this sitting"), and lets it run. When the sitting returns, the orchestrator re-reads `tasks.md`: if work remains, it re-invokes `speckit-implement`. The loop terminates when `tasks.md` shows no remaining tasks. The user is informed up-front that implementation may take several sittings and why. The user is not asked to choose chunk size, and the orchestrator does not impose its own chunking heuristic.

**Why this priority**: This is the core behavior change requested. Today the implement subagent's per-sitting suggestion surfaces inside `/speckit-flow` as a question to the user; the user has to answer it. This story replaces that handoff with an orchestrator-driven loop that simply accepts the subagent's suggestion each time and continues until done.

**Independent Test**: Run `/speckit-flow` on any feature whose `tasks.md` has been generated and verify that (a) the user is never asked to choose how much to do in a sitting, (b) the implement phase invokes `speckit-implement` more than once when its first-sitting suggestion does not cover all tasks, and (c) the loop terminates exactly when `tasks.md` has no remaining unchecked tasks.

**Acceptance Scenarios**:

1. **Given** `tasks.md` is too large for `speckit-implement` to finish in one sitting, **When** the orchestrator enters Phase 6, **Then** it invokes `speckit-implement` repeatedly — accepting each sitting's surfaced suggestion — until `tasks.md` is fully complete, never asking the user to choose chunk size.
2. **Given** `speckit-implement` completes everything in its first sitting, **When** the orchestrator re-reads `tasks.md` and sees no remaining tasks, **Then** it exits Phase 6 without spawning a second sitting.
3. **Given** the user starts `/speckit-flow` and reaches implementation, **When** the implement subagent's "how much should I do in this sitting?" suggestion would previously have been forwarded to the user, **Then** the orchestrator auto-accepts that suggestion instead and proceeds.

---

### User Story 2 - Continuity across sittings (Priority: P1)

Because each `speckit-implement` invocation runs in an isolated subagent context, every sitting must start with a correct picture of what is already done. After each sitting, the implemented tasks are marked complete on disk; before each new sitting begins, the orchestrator checks the current state of `tasks.md` to decide whether the loop continues, and the next subagent invocation reads `tasks.md` fresh to know what to do next.

**Why this priority**: Without on-disk continuity, the second sitting would either redo finished work or skip ahead and lose dependencies. This story is what makes multi-sitting implementation correct rather than just chunked. It is P1 because no chunking scheme is acceptable if it produces wrong output.

**Independent Test**: Force a multi-sitting run, inspect `tasks.md` between sittings, confirm completed tasks are checked off, and confirm the next subagent invocation picks up by reading the current file state.

**Acceptance Scenarios**:

1. **Given** the first sitting completes part of the work, **When** the second sitting starts, **Then** `tasks.md` already shows the completed tasks as done and the second subagent picks up by reading the current file (no orchestrator-supplied task list).
2. **Given** a sitting fails partway through, **When** the orchestrator surfaces the failure, **Then** the on-disk state reflects only what truly completed, and no false completions are claimed.
3. **Given** the user re-runs `/speckit-flow` after a session interruption, **When** the orchestrator reaches implementation, **Then** it resumes by re-invoking `speckit-implement` against the current `tasks.md` rather than restarting at task 1.

---

### User Story 3 - Visible progress with a stop hatch (Priority: P2)

Between sittings the orchestrator emits a short progress note — tasks completed this sitting, tasks remaining — and auto-continues into the next sitting. The user is not asked for permission per sitting. The progress note exists so the user can see the loop is alive and can choose to halt it by saying "stop" (or interrupting); if no such signal arrives, the orchestrator just keeps going until `tasks.md` is fully done.

**Why this priority**: Useful for trust and for long runs where the user may want to inspect intermediate state, but the loop works without it. P2 because the feature still delivers value with no progress notes at all (the loop just runs to completion); the notes are the visibility layer.

**Independent Test**: Watch a multi-sitting run and verify (a) one progress note appears between each pair of sittings, (b) the orchestrator does not ask for confirmation between sittings, (c) typing "stop" between sittings cleanly ends the flow with on-disk state preserved, and (d) when `tasks.md` is fully done no further note or prompt appears.

**Acceptance Scenarios**:

1. **Given** a sitting just returned and unchecked tasks remain in `tasks.md`, **When** the orchestrator prepares the next sitting, **Then** it emits a concise progress note and re-invokes `speckit-implement` without waiting for the user.
2. **Given** the user types "stop" between sittings, **When** the orchestrator sees the signal, **Then** the loop halts, on-disk state is preserved, and the user can resume later by re-running `/speckit-flow`.
3. **Given** `tasks.md` shows no remaining unchecked tasks after a sitting, **When** the orchestrator finishes Phase 6, **Then** no further progress note or prompt appears and the flow proceeds to the final summary.

---

### Edge Cases

- What happens when `tasks.md` is empty or contains only tasks already marked done? The orchestrator skips the loop entirely with a clear "nothing to do" message; no subagent is spawned.
- How does the system handle a sitting that returns without completing any task (the subagent gave up early)? The orchestrator does not silently retry; it surfaces the zero-progress condition and halts the loop.
- What happens if the user edits `tasks.md` (adds, removes, or reorders tasks) between sittings? The next loop iteration reads the file fresh, so the change is absorbed automatically. No special handling is required from the orchestrator.
- What happens when the implementation fits a single sitting? The loop runs once, terminates on the first disk re-read (no unchecked tasks remain), and the orchestrator emits no progress note for a non-existent gap.
- What happens when the user previously answered the now-removed "how much?" question (muscle memory) and types a number during Phase 6? The orchestrator ignores it; the implement subagent's own suggestion is the only chunking signal.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The orchestrator MUST NOT impose a chunking heuristic. The per-sitting boundary is decided by `speckit-implement` itself (its own surfaced suggestion). The orchestrator's role is to invoke, observe, and loop.
- **FR-002**: The orchestrator MUST auto-accept the implement subagent's per-sitting suggestion. The legacy "how much should I do in this sitting?" question MUST NOT be forwarded to the user during `/speckit-flow`.
- **FR-003**: The orchestrator MUST inform the user, before the first implementation sitting begins, that implementation may run across several sittings and why (context efficiency per subagent).
- **FR-004**: Each implementation sitting MUST run in its own isolated `speckit-implement` subagent invocation. The orchestrator MUST NOT pass a pre-partitioned task subset; the subagent reads `tasks.md` itself to know what is still to do.
- **FR-005**: After each sitting, the orchestrator MUST re-read `tasks.md` from disk to determine whether unchecked tasks remain. This disk re-read is the sole signal used to decide whether to loop again.
- **FR-006**: The loop MUST terminate when `tasks.md` shows no remaining unchecked tasks. Termination MUST be observed from disk, not inferred from the subagent's returned message.
- **FR-007**: If a sitting returns without checking off any task (i.e., zero progress on disk), the orchestrator MUST surface the condition and stop the loop; it MUST NOT auto-retry the same invocation.
- **FR-008**: The orchestrator MUST treat `tasks.md` as the sole source of truth for what has been done; the implement subagent's returned message MAY be used as a status hint only, never as the authoritative state.
- **FR-009**: If `tasks.md` is missing, empty, or fully checked off at the start of Phase 6, the orchestrator MUST skip the implement loop and report the state to the user instead of spawning an empty subagent.
- **FR-010**: Between sittings (when unchecked tasks remain), the orchestrator MUST emit a concise progress note (e.g., tasks completed in the last sitting, total remaining) and then auto-continue into the next sitting. It MUST NOT ask the user for per-sitting confirmation.
- **FR-011**: The user MUST be able to halt the loop between sittings by signalling "stop" (or equivalent interruption). On stop, the orchestrator MUST exit cleanly with on-disk state preserved so a subsequent `/speckit-flow` run can resume from current `tasks.md` state.
- **FR-012**: The orchestrator MUST NOT introduce any new user-facing question during Phase 6 beyond the optional in-flight "stop" signal. Specifically, no chunk-size, batch-count, or per-sitting continue prompt is permitted.

### Key Entities *(include if feature involves data)*

- **Sitting**: One invocation of the `speckit-implement` subagent. The subagent itself chooses how much of `tasks.md` to take on for this sitting; the orchestrator does not partition. Each sitting produces on-disk updates to the project and to `tasks.md`'s checkbox state.
- **Progress note**: A short between-sittings message the orchestrator emits, describing what completed in the last sitting and how many tasks remain. Informational only — it does not request a response.
- **Stop signal**: A user-supplied "stop" (or equivalent interruption) between sittings that ends the loop cleanly. The only user-facing control during Phase 6.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: When `/speckit-flow` enters the implementation phase, the user is asked zero questions about chunk size, batch count, or per-sitting continuation.
- **SC-002**: For feature task lists where the old single-sitting flow would exhaust the subagent's working context, the new flow completes implementation across multiple sittings without context-exhaustion errors in 100% of runs.
- **SC-003**: When a multi-sitting run is interrupted (user stop, session ends, sitting failure) and the user restarts `/speckit-flow`, the resumed run picks up against current `tasks.md` state in 100% of cases — never restarts at task 1 and never silently re-does a completed task.
- **SC-004**: The implementation phase emits exactly one progress note per gap between sittings (zero notes when the loop runs to completion in a single sitting). No other user-facing message is introduced by this feature except the final summary.
- **SC-005**: For task lists that fit a single sitting, the user-visible time-to-completion of the implementation phase is no worse than it was before this feature shipped.

## Assumptions

- `tasks.md` already encodes task dependency order, and the `speckit-implement` subagent already reads it to decide what to take on per sitting. The orchestrator does not need to re-derive dependencies or partition the file — that decision belongs to the subagent.
- The `speckit-implement` subagent already records its progress by checking tasks off in `tasks.md`. If it does not, that on-disk persistence is treated as a prerequisite for this feature, not a new requirement introduced here.
- The `speckit-implement` subagent already surfaces a per-sitting suggestion of how much it intends to do; this feature reuses that signal by accepting it (instead of forwarding it to the user) and treating it as the implicit sitting boundary.
- If the user edits `tasks.md` between sittings (adds, removes, or reorders tasks), the loop absorbs the changes naturally: the orchestrator's loop-termination check and the next subagent invocation both read the file fresh. No special handling is needed.
- "Context efficiency" is interpreted as a working-memory concern for the implement subagent — the subagent owns the chunking call, so this spec does not prescribe a heuristic.
- Constitution Principle V ("Disk is truth") and Principle I ("Subagent Phase Isolation") apply unchanged: chunking does not introduce shared state between sittings beyond `tasks.md`.
