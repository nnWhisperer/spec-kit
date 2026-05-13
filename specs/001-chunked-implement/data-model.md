# Phase 1 Data Model: Chunked Implementation in /speckit-flow

This feature has **no persistent data model**. It manages a process loop, not data. The Key Entities in `spec.md` ("Sitting", "Progress note", "Stop signal") describe runtime concepts, not records.

The only on-disk state involved is `tasks.md`, which this feature **consumes** (read-only from the orchestrator's point of view) and whose schema is **owned by `speckit-tasks`**, not by this feature. For completeness, the consumed schema is:

## Consumed schema: `tasks.md` checkbox lines

| Element | Format | Owner | Notes |
|---------|--------|-------|-------|
| Open task | `- [ ] T### …` at start of line | `speckit-tasks` (writer) | Counted by the orchestrator's loop-termination check. |
| Completed task | `- [X] T### …` (or `[x]`) at start of line | `speckit-implement` (writer) | Used in `OPEN_BEFORE - OPEN_AFTER` to compute "tasks done this sitting." |
| Section header / narrative | Any other line | — | Ignored by the count. |

The orchestrator never writes to `tasks.md`. Constitution Principle IV forbids it.

## Runtime concepts (in-memory, single-turn)

These exist only within a single execution of Phase 6 and have no file representation:

- **`OPEN_BEFORE` / `OPEN_AFTER`**: Integers captured from `count-open-tasks.sh` before and after each `Agent` call. Used both for the termination check (`OPEN_AFTER == 0` → done) and the zero-progress guard (`OPEN_AFTER >= OPEN_BEFORE` → stop, surface).
- **`SITTING_INDEX`**: 1-based counter incremented per sitting. Used only in the progress note string ("Sitting 2 complete: …"). Not persisted.

## Schema we deliberately do not introduce

- No "session state" JSON or YAML file recording sitting count, current batch, etc. The whole point of the design is that `tasks.md` is sufficient to resume; adding a session file would create a second source of truth and a new failure mode (file out-of-sync with checkboxes).
- No metadata about which subagent invocation completed which task. Already implicitly tracked by git commits (if the user runs the `after_implement` git commit hook) or simply by file mtime.
