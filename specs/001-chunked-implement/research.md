# Phase 0 Research: Chunked Implementation in /speckit-flow

There are no `NEEDS CLARIFICATION` markers in the Technical Context. The decisions below are not unknowns — they are calls that the orchestrator's implementation must make. Each is recorded here so the implementation in Phase 2 (tasks.md / code) follows them without re-deriving.

---

## Decision 1: How is per-sitting scope communicated to `speckit-implement`?

**Decision**: Don't communicate scope. Invoke `speckit-implement` with a near-empty prompt (`"Execute tasks.md."`). Let the subagent read `tasks.md` and decide what to take on.

**Rationale**: The implement subagent body (generated from `templates/commands/implement.md`) already (a) reads `tasks.md`, (b) executes phase-by-phase, (c) marks completed tasks `[X]` on disk as it goes. Each invocation will naturally take on as much as fits its context budget, then return. Passing a "do tasks N through M" prompt would be the orchestrator pre-partitioning, which the spec explicitly forbids (FR-001, FR-004). The Clarifications Q1 answer confirms: the orchestrator never partitions.

**Alternatives considered**:
- *Pass a "this is sitting K of an unknown total; do what you can and return" prompt.* Rejected: that's a wrapper instruction trying to coach the subagent, which is exactly what Constitution Principle II warns against (the agent body is verbatim from upstream — wrapping it with sub-instructions creates drift).
- *Pass the unchecked task IDs as the prompt.* Rejected: that *is* partitioning, and it also duplicates information already on disk (Principle V).

---

## Decision 2: How does the orchestrator detect "done"?

**Decision**: After each sitting, run `bash scripts/bash/count-open-tasks.sh <feature-dir>/tasks.md` and parse the integer. Zero → terminate the loop. Positive → re-invoke.

The helper script is a single line: `grep -c '^- \[ \]' "$1"` (with appropriate `set -euo pipefail` and `|| true` to handle the grep-found-nothing exit code).

**Rationale**: Disk is truth. The subagent's return message can omit, paraphrase, or misreport completion ("I finished US1!" while leaving an unchecked task behind). A grep over `tasks.md` is unambiguous, cheap (<10ms), and matches exactly the format the subagent itself writes.

The choice of `grep` over a Python/AWK parser is deliberate: bash + grep is already the toolchain for every other helper in `scripts/bash/`, and the format is simple enough that no real parser is needed.

**Alternatives considered**:
- *Parse the subagent's return message for "all done" markers.* Rejected: violates Principle V.
- *Have the subagent write a sentinel file on completion.* Rejected: introduces a second state location and a new failure mode (sentinel written, tasks.md inconsistent).
- *Count `[X]` instead of `[ ]` and compare to total.* Rejected: needs two greps and a subtraction; counting open tasks is the direct question.

---

## Decision 3: How does the orchestrator detect a zero-progress sitting?

**Decision**: Capture the open-task count before the Agent call (`OPEN_BEFORE`) and after (`OPEN_AFTER`). If `OPEN_AFTER >= OPEN_BEFORE`, the sitting made no on-disk progress — halt the loop and surface the condition to the user (FR-007).

**Rationale**: A subagent can return without crashing yet without checking off any task — e.g., it hit a blocker, decided to ask a question that never got asked back, or its body short-circuited. Auto-retrying that invocation is forbidden (FR-007, mirroring Constitution Principle IV's "no auto-retry"). Comparing counts is the same disk-is-truth check that drives termination, so the same helper script answers both questions.

**Alternatives considered**:
- *Cap retries (e.g., up to 3 attempts).* Rejected: directly contradicts Principle IV. Surfacing failure is the orchestrator's job; deciding whether to re-run belongs to the user.
- *Inspect the subagent's return text for "blocked" or "failed".* Rejected: Principle V.

---

## Decision 4: What does the between-sittings progress note look like?

**Decision**: One short line of orchestrator text emitted before the next Agent call, then immediately the next call. Shape:

```
Sitting K complete: N tasks done this sitting, M remaining. Continuing…
```

No `AskUserQuestion`. No waiting for confirmation. The note is informational; the next Agent invocation fires in the same assistant turn.

**Rationale**: Clarifications Q2 settled this as "auto-continue with stop hatch." In Claude Code, the user's only available "stop" channel between sittings is to interrupt the assistant's turn (Escape/Ctrl+C); explicit `AskUserQuestion` between sittings would violate FR-002 / FR-012 (no per-sitting prompts). Emitting a text line right before the next tool call gives the user a moment to see progress and choose to interrupt, while preserving the autonomous loop when they don't.

The "N tasks done this sitting" figure is computed from `OPEN_BEFORE - OPEN_AFTER`. The "M remaining" is `OPEN_AFTER`.

**Alternatives considered**:
- *Verbose multi-line summary with completed-task list.* Rejected: noisy; encourages the user to read instead of trusting the disk artifact (which they can inspect themselves).
- *Silent loop (no progress note).* Rejected: violates SC-004 / US3 — the note is the visibility layer that lets the user know the loop is alive.

---

## Decision 5: What does the orchestrator do when the user says "stop"?

**Decision**: The orchestrator doesn't actively poll for "stop." When the user interrupts the turn and types a "stop" / "halt" / "pause" message, the next turn's orchestrator sees that message via the standard Claude Code input flow and chooses not to re-enter the loop. State on disk (`tasks.md` checkboxes) is already preserved by the subagent's per-task writes; nothing extra is needed.

**Rationale**: There is no real-time keyboard mechanism inside a tool turn; Claude Code's interrupt is the only "stop" signal available. FR-011 was written knowing this — the on-disk state guarantee is the contract, not any "graceful shutdown" handler.

**Alternatives considered**:
- *Implement an `AskUserQuestion` with "stop / continue" between sittings, defaulting to continue.* Rejected: violates FR-012 (no per-sitting prompts). Even a default-yes question is still a question.
- *Write a flag file the user can `touch` to stop.* Rejected: out-of-band channel for a problem already solved by turn interrupts.

---

## Decision 6: Where does the helper script live?

**Decision**: `scripts/bash/count-open-tasks.sh`. Pattern matches the other helpers (`check-prerequisites.sh`, `create-new-feature.sh`, `setup-plan.sh`).

**Rationale**: Consistency with the rest of the bash/ directory. Single-purpose, hyphen-cased name. Powershell parity is *not* added in this feature — the rest of the repo's powershell mirroring already lags for several scripts; adding `count-open-tasks.ps1` is a follow-up, not part of this feature's scope.

**Alternatives considered**:
- *Inline the `grep -c` in the orchestrator's Bash tool call.* Rejected: testability — a named script can be invoked from a terminal during quickstart verification, and the orchestrator's Bash invocation reads more clearly with a named command than with inline grep.

---

## Out-of-scope, deferred

- **Powershell parity** for the new helper. Add when someone next touches the powershell directory.
- **Configurable progress-note verbosity**. The note format is fixed; if users want richer telemetry, that is a separate feature.
- **A subagent invocation prompt that explicitly says "do what fits in one sitting."** Tempting, but adding it would be the orchestrator coaching the subagent — exactly what Principle II is meant to prevent. Re-visit only if real-world runs show the subagent ignoring its own pacing.
