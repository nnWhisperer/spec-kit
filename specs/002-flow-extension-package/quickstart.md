# Quickstart: Verify the Subagent-Flow Extension Locally

**Feature**: 002-flow-extension-package
**Date**: 2026-05-13
**Audience**: developer working on this feature (validating the implementation), maintainer (verifying a release candidate before publishing), reviewer.

This is the manual end-to-end walkthrough. There is no automated test framework for the orchestration delta; verification is by direct observation against the success criteria in spec.md.

---

## Prerequisites

- A working `specify` CLI installed (`pip install spec-kit` or equivalent).
- A Bash shell (the shipped scripts are Bash-only).
- Claude Code as the host AI agent (the reference host; other agents are out of scope per spec Assumption).
- For the maintainer-CI verification step (optional): `nektos/act` installed locally and a Docker daemon running.

---

## Step 0 — Build the extension payload (developer only)

If you are the developer adding this feature, build the extension directory before installing it. The maintainer running CI will already have this step done by the workflow; the developer doing local testing runs it once by hand. This step bakes the SOURCE copies of the seven agent files — the orchestrator's inline bootstrap will deploy them to `.claude/agents/` later, after install and on first invocation.

```bash
cd <fork-repo-root>
SRC_DIR=templates/commands \
OUT_DIR=extensions/subagent-flow/agents \
bash extensions/subagent-flow/scripts/bash/build-claude-agents.sh
```

Expected output: `done: 7 agent file(s) written, 2 skipped` (two skipped = `clarify` and `constitution`). Verify:

```bash
ls extensions/subagent-flow/agents/
# speckit-analyze.md speckit-checklist.md speckit-implement.md speckit-plan.md
# speckit-specify.md speckit-tasks.md speckit-taskstoissues.md
```

Seven files. Each starts with `---`, contains a `name: speckit-<phase>` line, contains the `AUTO-GENERATED` warning header. These are the source copies that ship inside the extension; the orchestrator's bootstrap will copy them to `.claude/agents/` in Step 2.

---

## Step 1 — Install into a clean project (source dir populated; `.claude/agents/` NOT yet populated)

Create a fresh spec-kit project (or use an existing one with no `subagent-flow` already installed):

```bash
cd $(mktemp -d)
specify init my-test-project
cd my-test-project
```

Install the extension from the local dev path:

```bash
specify extension add --dev <fork-repo-root>/extensions/subagent-flow
```

**Expected at install time** (US1, FR-001; Path 3 per research.md Decision 6 + Decision 9):
- Command succeeds.
- `specify extension list` shows `subagent-flow (v1.0.0)` as installed.
- `.specify/extensions/subagent-flow/` exists and contains `extension.yml`, `commands/`, `scripts/bash/`, `README.md`, and `agents/`.
- `.claude/commands/` contains a registered link/copy of the orchestrator (depending on the host agent's registration scheme).
- `.specify/extensions/subagent-flow/agents/` contains the seven baked source files.
- `.claude/agents/` MAY NOT yet contain any `speckit-*.md` files. Population happens on first orchestrator invocation, not at install time. This is deliberate (no spec-kit core change required; the orchestrator's inline bootstrap owns deployment).

Verify the seven baked SOURCE files were copied into the extension's payload directory:

```bash
ls .specify/extensions/subagent-flow/agents/speckit-*.md
# Should list exactly the seven phase files.
head -10 .specify/extensions/subagent-flow/agents/speckit-implement.md
# First lines should show frontmatter with name, description, tools=Read, Write, Edit, Bash, Glob, Grep, TodoWrite,
# followed by the AUTO-GENERATED header.
```

Verify `.claude/agents/` is not yet populated (or, if it is from a previous run, that the bootstrap will handle it):

```bash
ls .claude/agents/speckit-*.md 2>/dev/null
# Either empty/no-such-file, or already populated from a prior session.
# Either way, the bootstrap on first invocation will make it correct.
```

Verify the helper script is reachable from the orchestrator's body (US1 acceptance #3, FR-005):

```bash
bash .specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh /dev/null
# 0
grep -q '.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh' \
  .specify/extensions/subagent-flow/commands/speckit.subagent-flow.run.md
echo "exit=$?"
# exit=0 — the orchestrator body references the installed helper path.
```

Verify the orchestrator body contains the inline bootstrap block:

```bash
grep -q 'cmp -s' .specify/extensions/subagent-flow/commands/speckit.subagent-flow.run.md
echo "exit=$?"
# exit=0 — the bootstrap's content-comparison primitive is present.
grep -q '.specify/extensions/subagent-flow/agents' \
  .specify/extensions/subagent-flow/commands/speckit.subagent-flow.run.md
echo "exit=$?"
# exit=0 — the bootstrap references the source dir.
```

---

## Step 2 — Invoke the orchestrator once to populate `.claude/agents/` transparently

In your AI agent (Claude Code), invoke:

```
/speckit.subagent-flow.run

Add a /healthz endpoint that returns {"status": "ok"} as JSON.
```

**Expected at first invocation** (US1 acceptance #2, FR-008; US2; Path 3 transparent bootstrap):
- The orchestrator's inline bootstrap block runs first (silent). It detects that `.claude/agents/speckit-*.md` is missing (or empty), `cmp -s`-diffs each source against its deployed counterpart, finds the deployed copies absent, and `cp`s each source file into place. No prompt is shown to the user.
- Phase 1 (`specify`) runs in an isolated subagent; `specs/<NNN-healthz>/spec.md` is created.
- Phase 2 (`clarify`) runs inline via the `Skill` tool, asks targeted questions, updates `spec.md`.
- Phases 3–4 (`plan`, `tasks`) run as subagents; `plan.md` and `tasks.md` are written.
- Phase 5 (`analyze`) is offered as an optional pass.
- Phase 6 (`implement`) runs one or more sittings depending on the size of `tasks.md`. Each sitting reads the helper, decides whether to loop. Final summary lists number of sittings.

Verify the bootstrap populated `.claude/agents/` and the deployed copies content-match the source:

```bash
ls .claude/agents/speckit-*.md
# Should now list exactly the seven phase files:
# speckit-analyze.md  speckit-checklist.md  speckit-implement.md  speckit-plan.md
# speckit-specify.md  speckit-tasks.md      speckit-taskstoissues.md

for p in specify plan tasks analyze implement checklist taskstoissues; do
  cmp -s ".specify/extensions/subagent-flow/agents/speckit-$p.md" \
         ".claude/agents/speckit-$p.md" \
    || echo "MISMATCH: speckit-$p"
done
# Should print nothing — every deployed copy content-matches its source.
```

---

## Step 3 — Verify the chunked implement loop (US3, FR-008, SC-003)

Craft a feature whose initial `tasks.md` has at least twice as many open tasks as one sitting can plausibly close (≥ 60 unchecked tasks is a generous safety margin). Run `/speckit.subagent-flow.run` against it. Observe:

- Between sittings, the orchestrator emits the progress note `Sitting K complete: ... tasks done this sitting, ... remaining. Continuing…`.
- The orchestrator does NOT call `AskUserQuestion` between sittings.
- The helper is invoked between every sitting (visible in tool-use logs).
- When `count-open-tasks.sh` returns 0, the loop exits cleanly.

---

## Step 4 — Verify the bootstrap's self-healing and the FR-013 source-missing error path

### Step 4a — Self-healing (recoverable case): delete a deployed copy

Simulate a user-deleted deployed file:

```bash
rm .claude/agents/speckit-tasks.md
```

Invoke `/speckit.subagent-flow.run` again. **Expected** (Path 3 self-heal):

- The orchestrator's inline bootstrap detects that `.claude/agents/speckit-tasks.md` is missing; `cmp -s` reports mismatch (one side absent); `cp` restores it from the source at `.specify/extensions/subagent-flow/agents/speckit-tasks.md`.
- The user observes no error. The orchestrator proceeds straight to Phase 1.
- Verify the file is restored and content-matches:

```bash
cmp -s .specify/extensions/subagent-flow/agents/speckit-tasks.md \
       .claude/agents/speckit-tasks.md
echo "exit=$?"
# exit=0 — bootstrap restored the file from source.
```

### Step 4b — Self-healing (upgrade-drift case): tamper with a deployed copy

Simulate stale content from a prior version:

```bash
echo "# tampered" > .claude/agents/speckit-plan.md
```

Invoke `/speckit.subagent-flow.run` again. **Expected**:

- The bootstrap's `cmp -s` detects content drift between source and deployed; `cp` overwrites the tampered file with the source content.
- The user observes no error. The orchestrator proceeds to Phase 1.
- Hand-edits are not preserved (the agent files carry the `AUTO-GENERATED` header for this reason; spec edge case documents this).

### Step 4c — Unrecoverable case: source dir missing (FR-013 error path)

Simulate a corrupted install by deleting the SOURCE dir (e.g., the extension dir was manually removed without using `specify extension remove`):

```bash
rm -rf .specify/extensions/subagent-flow/agents/
```

Invoke `/speckit.subagent-flow.run` again. **Expected** (FR-013, U1-pinned literal-element contract, Path 3 form):

- The orchestrator's bootstrap detects that the source dir is missing and emits an error message whose body contains all three of the following literal elements:
  - (a) the literal list of missing source paths (the seven `.specify/extensions/subagent-flow/agents/speckit-<phase>.md` paths, or the source-dir path itself);
  - (b) the recovery command verbatim: `specify extension add subagent-flow`;
  - (c) the README path verbatim: `.specify/extensions/subagent-flow/README.md`.
- The orchestrator MUST exit 1 before invoking any subagent. The `Agent` tool is not called in this state. The user must NOT see a generic "subagent not found" error from the `Agent` tool — the bootstrap catches the failure first.

Recover by re-installing the extension:

```bash
specify extension add --dev <fork-repo-root>/extensions/subagent-flow
```

Re-invoke `/speckit.subagent-flow.run` to confirm the bootstrap passes again.

---

## Step 5 — Verify upstream commands still work (US4, FR-009, SC-004)

The extension must not shadow upstream commands. From the same project:

```
/speckit.specify

Add a /readyz endpoint.
```

**Expected**: the upstream `/speckit.specify` runs unchanged; no namespace collision with the extension's command.

```bash
specify extension list
# Confirms exactly one registration for subagent-flow.
```

---

## Step 6 — Verify clean uninstall (US5, FR-010, SC-004)

```bash
specify extension remove subagent-flow
```

**Expected** (Path 3 per research.md Decision 6):
- The slash command `/speckit.subagent-flow.run` is no longer registered.
- `.specify/extensions/subagent-flow/` is gone — the entire source dir (including the seven baked source files, the helper script, the regen script, the manifest, and the README) is removed cleanly.
- The seven `.claude/agents/speckit-*.md` files are **deliberately left in place**. They belong to the user's project after bootstrap (the orchestrator copied them there, not the installer) and they contain upstream-derived content that remains useful for the user's direct `/speckit.<phase>` invocations. This is documented in the README as deliberate, not a bug.
- `specify extension list` no longer shows `subagent-flow`.

Verify the deployed copies persisted:

```bash
ls .claude/agents/speckit-*.md
# Still lists the seven phase files.

ls .specify/extensions/subagent-flow/ 2>/dev/null
# No output — the extension dir is gone.
```

Verify upstream commands still work:

```
/speckit.specify

Add a /pingz endpoint.
```

Optionally scrub the deployed agent files (the README documents this one-liner for users who want to remove them):

```bash
rm .claude/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md
```

Then re-install:

```bash
specify extension add --dev <fork-repo-root>/extensions/subagent-flow
```

Verify no duplicate registration appears (`specify extension list` shows exactly one `subagent-flow` entry, SC-005). On the next `/speckit.subagent-flow.run` invocation, the bootstrap will re-populate `.claude/agents/` from the freshly-installed source dir — whether or not you scrubbed the deployed copies in the previous step.

---

## Step 7 — Verify the `--keep-config` flag is a no-op

Per research.md Decision 6 (Path 3), this extension does not own any config files. The deployed agent copies at `.claude/agents/` are not "config" — they are the user's after-bootstrap state — and the default uninstall already leaves them in place. The `--keep-config` flag therefore has nothing to preserve and is documented as a no-op:

```bash
specify extension add --dev <fork-repo-root>/extensions/subagent-flow
# (Invoke /speckit.subagent-flow.run once in the AI agent so the bootstrap populates .claude/agents/.)
specify extension remove subagent-flow --keep-config
ls .claude/agents/speckit-*.md
# The seven files are still there — identical to the default Step 6 remove without the flag.
ls .specify/extensions/subagent-flow/ 2>/dev/null
# No output — the extension dir is gone, identical to Step 6.
```

The `--keep-config` flag is preserved in the README's Uninstall section purely for symmetry with other spec-kit extensions; passing it produces no behavioural difference for `subagent-flow`.

---

## Step 8 — Verify the maintainer CI workflow locally (constraint #1)

This step is for the maintainer or the developer working on the workflow. Skip if you only care about user-side install/uninstall.

```bash
cd <fork-repo-root>
act workflow_dispatch \
    -W .github/workflows/subagent-flow-resync.yml \
    --container-architecture linux/amd64
```

**Expected**:
- `act` runs the workflow inside a Docker container.
- The checkout, generator, and diff steps complete without error.
- If `templates/commands/*.md` has drifted from the baked `extensions/subagent-flow/agents/*.md`, the workflow runs the `create-pull-request` step (or, locally under `act`, prints what it *would* do — `act` does not actually push PRs).
- If no drift, the workflow exits cleanly.

The README's maintainer section documents this same invocation.

---

## Step 9 — Verify the README is sufficient on first read (SC-007)

Hand the README to a colleague who has never seen the fork. Watch them:

1. Install the extension by following the README only.
2. Invoke the orchestrator on a small feature.
3. Uninstall.

If they succeed without consulting any other file in the repo, SC-007 is satisfied. If they get stuck, fix the README before release.

---

## Cleanup

```bash
specify extension remove subagent-flow
cd ..
rm -rf my-test-project
```

---

## Pass/fail summary

A successful run of this quickstart satisfies:

| Step | Verifies |
|---|---|
| Step 0 | FR-006, FR-007, FR-011 (generator idempotent and skips correct phases) |
| Step 1 | US1, FR-001, FR-002, FR-003, FR-004 (source-dir population), FR-005, FR-014, presence of bootstrap markers in orchestrator body |
| Step 2 | US1 acceptance #2, US2 (transparent bootstrap deploys to `.claude/agents/`), FR-008, FR-013 (happy path), SC-001, SC-002 |
| Step 3 | US3, FR-008, SC-003 |
| Step 4a/b | FR-013 self-heal cases (deployed-copy missing, deployed-copy stale) |
| Step 4c | FR-013 source-missing error path (the only user-visible bootstrap error under Path 3) |
| Step 5 | US4, FR-009 |
| Step 6 | US5, FR-010, SC-004 (Path 3 uninstall: source dir removed, deployed copies persist) |
| Step 7 | `--keep-config` no-op (Decision 6 Path 3 form) |
| Step 8 | Constraint #1 (act-compatible workflow), SC-006 |
| Step 9 | SC-007 |

If any step diverges from "Expected", file an issue and do not release.
