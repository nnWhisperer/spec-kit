---
description: "Dependency-ordered task list for the subagent-flow extension package (Path 3 — orchestrator-owned transparent bootstrap)"
---

# Tasks: Subagent Orchestration as Installable Extension

**Input**: Design documents from `/specs/002-flow-extension-package/`
**Prerequisites**: plan.md (loaded), spec.md (loaded — five user stories), research.md (nine decisions, Path 3 finalised), data-model.md (two-state lifecycle for agent files), contracts/extension-manifest.yml (no `provides.agents`, no hooks), quickstart.md (Steps 0–9 including 4a/4b/4c bootstrap-behaviour verification)

**Tests**: No automated test framework exists for the Markdown/Bash deliverable. Verification is via the manual quickstart (`specs/002-flow-extension-package/quickstart.md`) and `bash -n` syntax checks plus targeted `cmp -s` content equality checks for the two-state agent-file lifecycle. No TDD test tasks are generated; quickstart-driven verification tasks appear inside each user-story phase and in the polish phase.

**Organization**: Tasks are grouped by user story (US1–US5) so each story can be implemented and verified independently against its quickstart step. Path 3 means the orchestrator's command body owns the bootstrap that deploys agent files from `.specify/extensions/subagent-flow/agents/` (source copy) to `.claude/agents/` (deployed copy) on first invocation — there are no install-lifecycle hooks and no `provides.agents` manifest block.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US5 maps to spec.md user stories; setup/foundational/polish tasks omit the label
- Every task includes the absolute repository-relative file path it writes to or reads

## Path Conventions

This is a spec-kit extension package (no `src/`, no `tests/`). Paths are repository-relative under `/tmp/spec-kit/`:

- New extension payload: `extensions/subagent-flow/...`
- Maintainer CI: `.github/workflows/subagent-flow-resync.yml`
- Catalog: `extensions/catalog.community.json`
- Removed (per Decision 8): fork-root copies under `.claude/`, `scripts/bash/`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create the empty extension directory skeleton that every subsequent file lands in. No file content is authored here — only directories — so the rest of the work can proceed in parallel without `mkdir -p` race conditions inside individual tasks.

- [X] T001 Create directory `extensions/subagent-flow/` at `/tmp/spec-kit/extensions/subagent-flow/`
- [X] T002 [P] Create directory `extensions/subagent-flow/commands/` at `/tmp/spec-kit/extensions/subagent-flow/commands/`
- [X] T003 [P] Create directory `extensions/subagent-flow/scripts/bash/` at `/tmp/spec-kit/extensions/subagent-flow/scripts/bash/`
- [X] T004 [P] Create directory `extensions/subagent-flow/agents/` at `/tmp/spec-kit/extensions/subagent-flow/agents/`
- [X] T005 [P] Create directory `.github/workflows/` at `/tmp/spec-kit/.github/workflows/` (verify it does not already exist; if it does, skip silently)

**Checkpoint**: Directory skeleton ready. All payload files can now be written in parallel.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Move the two Bash helpers and write the manifest. These three files are referenced by every user story phase — the manifest names the single command (US1, US4), `count-open-tasks.sh` is the helper US3 verifies, and `build-claude-agents.sh` is the generator US2 uses to produce baked agents at maintainer time. Until they exist at the new paths, no user-story task can succeed.

**CRITICAL**: No user story work begins until this phase completes.

- [X] T006 [P] Copy `/tmp/spec-kit/scripts/bash/count-open-tasks.sh` to `/tmp/spec-kit/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` byte-for-byte (no edits; preserve executable bit via `chmod +x`)
- [X] T007 [P] Copy `/tmp/spec-kit/scripts/bash/build-claude-agents.sh` to `/tmp/spec-kit/extensions/subagent-flow/scripts/bash/build-claude-agents.sh` byte-for-byte (preserve executable bit). This is the generator; FR-006/FR-007/FR-011 require its behaviour to remain unchanged. The generator is an internal/power-user maintenance tool — it is NOT the bootstrap (the bootstrap is inline bash in the orchestrator body per Decision 9).
- [X] T008 Run `bash -n /tmp/spec-kit/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` and `bash -n /tmp/spec-kit/extensions/subagent-flow/scripts/bash/build-claude-agents.sh`; abort if either reports a syntax error.
- [X] T009 Write `/tmp/spec-kit/extensions/subagent-flow/extension.yml` from the canonical skeleton at `/tmp/spec-kit/specs/002-flow-extension-package/contracts/extension-manifest.yml`. Replace `<fork-owner>` placeholders in `repository`/`homepage` with the actual fork owner (or leave a single TODO marker if unknown). Validate against schema_version 1.0: `extension.id` matches `^[a-z0-9-]+$`, `extension.version` is `1.0.0`, `provides.commands[0].name` is `speckit.subagent-flow.run`, `requires.speckit_version` is `">=0.2.0"`, `requires.tools` is `[]` (FR-014). The manifest MUST NOT contain a `provides.agents` block, MUST NOT contain a `hooks` block, and MUST NOT contain any `defaults.agent_files` list — per Decision 6 (Path 3), agent-file provisioning is owned by the orchestrator's inline bootstrap, not by the manifest. (data-model.md §Entity: Extension Manifest.)

**Checkpoint**: Manifest and both Bash helpers live inside `extensions/subagent-flow/`. The extension directory is structurally complete enough that an installer could find and parse the manifest; user-story phases can begin.

---

## Phase 3: User Story 1 — Install Into a Fresh Project (Priority: P1) — MVP slice

**Goal**: A developer running `specify extension add --dev extensions/subagent-flow` against a clean spec-kit project ends up with the orchestrator slash command registered and the helper script reachable. The orchestrator's command body contains the inline bootstrap that will populate `.claude/agents/` on first invocation (Path 3).

**Independent Test** (quickstart Step 1): `specify extension add --dev extensions/subagent-flow` succeeds, `specify extension list` shows `subagent-flow (v1.0.0)`, `.specify/extensions/subagent-flow/` is populated (including the seven SOURCE-copy baked agents under `agents/`), and `bash .specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh /dev/null` prints `0`. Note: `.claude/agents/` is NOT expected to be populated at install time — the orchestrator's bootstrap deploys it on first invocation (verified separately in Phase 5 and Phase 8).

### Implementation for User Story 1

- [X] T010 [US1] Write `/tmp/spec-kit/extensions/subagent-flow/commands/speckit.subagent-flow.run.md`. Start from the existing fork orchestrator at `/tmp/spec-kit/.claude/commands/speckit-flow.md`, copy the body verbatim, then apply the first two of the three textual edits required by plan.md §Summary and data-model.md §Orchestrator Command File: (1) frontmatter `description:` updated to "Run the per-feature orchestrator end-to-end (specify → clarify → plan → tasks → optional analyze → implement)." matching the manifest, (2) every reference to `scripts/bash/count-open-tasks.sh` rewritten to `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` (Decision 7 — direct write, no installer rewrite). The third edit — inserting the inline bash bootstrap block at the very top of the body — is performed by T012 in a separate task so the bootstrap edit is reviewable on its own.
- [X] T011 [P] [US1] Edit `/tmp/spec-kit/extensions/catalog.community.json` to add a `subagent-flow` entry under `extensions` using the shape defined in data-model.md §Entity: Catalog Entry (fields: `name`, `id`, `description`, `author`, `version: "1.0.0"`, placeholder `download_url`, `repository`, `homepage`, `documentation`, `license: "MIT"`, `requires.speckit_version: ">=0.2.0"`, `provides: {commands: 1, hooks: 0}`, `tags: ["orchestrator", "subagent", "workflow", "claude-code"]`, `verified: false`, `downloads: 0`, `stars: 0`, `created_at`/`updated_at` set to `2026-05-13T00:00:00Z`). Preserve existing entries and JSON formatting; insert in alphabetical position relative to neighbours.
- [X] T012 [US1] Re-edit `/tmp/spec-kit/extensions/subagent-flow/commands/speckit.subagent-flow.run.md` to insert the inline bash bootstrap block at the very top of the orchestrator body, immediately after the frontmatter and before the first existing phase. The bootstrap MUST implement Decision 9 verbatim shape — approximately ten lines: set `SRC=.specify/extensions/subagent-flow/agents` and `DST=.claude/agents`; if `$SRC` is not a directory, emit a multiline `>&2` error containing all three of (a) the literal list of missing source paths under `$SRC` (one per line), (b) the recovery command verbatim `specify extension add subagent-flow`, and (c) the README path verbatim `.specify/extensions/subagent-flow/README.md`, then `exit 1`; `mkdir -p "$DST"`; `for p in specify plan tasks analyze implement checklist taskstoissues`: set `s="$SRC/speckit-$p.md"` and `d="$DST/speckit-$p.md"`, if `[ ! -f "$s" ]` emit per-file source-missing error to stderr with the same three literal elements and `exit 1`, else `cmp -s "$s" "$d" || cp "$s" "$d"`. The block MUST NOT prompt the user (no `AskUserQuestion`, no `read`). The block MUST NOT contain any runtime "option-a vs option-b" detection — Path 3 is the only path; manifest-shape branching is gone from the task graph. The bootstrap is the single mechanism that deploys SOURCE → DEPLOYED for agent files (FR-013, Path 3 form). This edit produces the third of the three textual edits from plan.md §Summary; combined with T010 the orchestrator body is complete.
- [X] T013 [US1] Smoke-validate the manifest by running spec-kit's own manifest parser (e.g., `python -c "from specify_cli.extensions import ExtensionManifest; ExtensionManifest.load('/tmp/spec-kit/extensions/subagent-flow/extension.yml')"`); fail if it errors. Confirm via re-parse that `provides.agents` is absent, `hooks` is absent, and `defaults` is absent — the manifest stays inside schema 1.0 with no custom keys (Decision 6 Path 3 lock-in). No runtime option detection occurs; no fallback path is exercised.

**Checkpoint**: US1 is independently testable per quickstart Step 1. The MVP-installable extension exists end-to-end. The orchestrator body is complete (verbatim plus three edits, including the inline bootstrap); the manifest is inert with respect to agent-file deployment; the baked agent SOURCE copies are supplied by US2 next.

---

## Phase 4: User Story 2 — Pre-Baked Subagent Files (Priority: P1)

**Goal**: The seven `speckit-<phase>.md` agent files ship pre-baked inside the extension at `extensions/subagent-flow/agents/`, generated against upstream `templates/commands/*.md`. After install, they live at `.specify/extensions/subagent-flow/agents/` as the SOURCE copy. The orchestrator's inline bootstrap (T012) is responsible for the SOURCE → DEPLOYED transition; this story produces the SOURCE side only.

**Independent Test** (quickstart Step 0 + Step 1 verification): `ls extensions/subagent-flow/agents/` shows seven files; each starts with `---`, contains a `name: speckit-<phase>` line, and contains the `AUTO-GENERATED` warning header. Re-running the generator produces byte-identical output (FR-011). After `specify extension add`, the seven SOURCE-copy files appear under `.specify/extensions/subagent-flow/agents/` — verified at the start of the deploy-lifecycle checks in Phase 8.

### Implementation for User Story 2

- [X] T014 [US2] Generate the seven pre-baked agent files into `/tmp/spec-kit/extensions/subagent-flow/agents/` by running `SRC_DIR=/tmp/spec-kit/templates/commands OUT_DIR=/tmp/spec-kit/extensions/subagent-flow/agents bash /tmp/spec-kit/extensions/subagent-flow/scripts/bash/build-claude-agents.sh`. Expect terminal output `done: 7 agent file(s) written, 2 skipped` (2 = clarify + constitution per FR-007). Fail if any other phase count appears.
- [X] T015 [US2] Verify generator output at `/tmp/spec-kit/extensions/subagent-flow/agents/`: assert exactly seven files (`speckit-specify.md`, `speckit-plan.md`, `speckit-tasks.md`, `speckit-analyze.md`, `speckit-implement.md`, `speckit-checklist.md`, `speckit-taskstoissues.md`); for each file assert (a) starts with `---`, (b) frontmatter `name:` matches the filename, (c) `AUTO-GENERATED from templates/commands/<phase>.md by scripts/bash/build-claude-agents.sh. Do not edit by hand.` header is present, (d) per-phase `tools:` matches the generator's `PHASE_TOOLS` map (plan: WebFetch/WebSearch added; implement: TodoWrite added; analyze/taskstoissues: read-only; others: `Read, Write, Edit, Bash, Glob, Grep`). Implements FR-007.
- [X] T016 [US2] Re-run the generator a second time with identical inputs and `diff -r /tmp/spec-kit/extensions/subagent-flow/agents/` against a `cp -r`-saved snapshot from before; assert zero diff (FR-011 idempotency, SC-005 reinforcement). Delete the snapshot afterwards.
- [X] T017 [US2] Write `/tmp/spec-kit/.github/workflows/subagent-flow-resync.yml` per research.md Decision 5 and data-model.md §Maintainer CI Workflow: triggers `workflow_dispatch` + `schedule: '0 6 * * 1'`; runner `ubuntu-latest`; steps = `actions/checkout@v4` (pinned), run `bash extensions/subagent-flow/scripts/bash/build-claude-agents.sh` with `SRC_DIR=templates/commands OUT_DIR=extensions/subagent-flow/agents`, `git diff --quiet extensions/subagent-flow/agents/` gate, then `peter-evans/create-pull-request@v6` (pinned) titled `chore(subagent-flow): resync agents against upstream`. Workflow MUST be `act`-compatible (constraint #1): no `pull_request_target`, no GitHub-only runners. T026 verifies act compatibility.

**Checkpoint**: US2 is independently testable per quickstart Step 0. The seven baked agents (SOURCE copies) are committed to the repo and the maintainer-CI workflow exists. There is no install-time copy step into `.claude/agents/` — that work belongs to the orchestrator's inline bootstrap added in T012, verified end-to-end in Phase 8.

---

## Phase 5: User Story 3 — Chunked Implement Loop Works After Install (Priority: P1)

**Goal**: The orchestrator's Phase 6 reads `tasks.md` between sittings via the installed helper using the exact path written into the orchestrator body in T010.

**Independent Test** (quickstart Step 3): On a feature with ≥60 unchecked tasks, the orchestrator runs more than one sitting, emits the progress note between sittings, invokes the helper at `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` every sitting, and terminates when the helper returns 0.

### Implementation for User Story 3

- [X] T018 [US3] Static-verify path coherence between orchestrator body and shipped helper: `grep -c '\.specify/extensions/subagent-flow/scripts/bash/count-open-tasks\.sh' /tmp/spec-kit/extensions/subagent-flow/commands/speckit.subagent-flow.run.md` MUST return ≥ 1; `test -f /tmp/spec-kit/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` MUST succeed. Together these enforce FR-005 (orchestrator-as-installed references helper-as-installed).
- [X] T019 [US3] Functional-test the helper against three inputs: (a) `bash /tmp/spec-kit/extensions/subagent-flow/scripts/bash/count-open-tasks.sh /dev/null` prints `0`; (b) a temp file with three `- [ ]` lines and two `- [x]` lines prints `3`; (c) a non-existent path prints `0` and exits 0. Implements the helper-contract validation rules from data-model.md §Entity: Open-Task Helper.

**Checkpoint**: US3 is independently testable per quickstart Step 3. The wiring between orchestrator body and helper is locked down statically and the helper itself behaves correctly.

---

## Phase 6: User Story 4 — Coexists With Upstream Per-Feature Commands (Priority: P2)

**Goal**: Installing the extension does not rename, remove, or shadow any upstream `/speckit.*` command. The extension's single command lives under the `speckit.subagent-flow.*` namespace.

**Independent Test** (quickstart Step 5): After install, every upstream slash command (`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.clarify`, `/speckit.analyze`, `/speckit.implement`, `/speckit.checklist`, `/speckit.taskstoissues`, `/speckit.constitution`) is still listed and works unchanged.

### Implementation for User Story 4

- [X] T020 [US4] Lint the manifest's command namespace: parse `/tmp/spec-kit/extensions/subagent-flow/extension.yml`, assert `provides.commands` length is exactly 1, and assert its `name` matches the regex `^speckit\.subagent-flow\.[a-z0-9-]+$` (data-model.md validation rule). Implements FR-003 and FR-009.
- [X] T021 [US4] Search the entire extension payload at `/tmp/spec-kit/extensions/subagent-flow/` for any string of the form `speckit.specify`, `speckit.plan`, `speckit.tasks`, `speckit.clarify`, `speckit.analyze`, `speckit.implement`, `speckit.checklist`, `speckit.taskstoissues`, `speckit.constitution` that appears in a context that would register or overwrite that command name (i.e., in the manifest's `provides.commands[].name` or in any registered command-name frontmatter). References *inside the orchestrator body* that delegate to those upstream commands via the `Agent`/`Skill` tools are allowed and expected — only registration-level collisions are forbidden. Implements FR-009.

**Checkpoint**: US4 is independently testable per quickstart Step 5. Namespace hygiene is statically verified.

---

## Phase 7: User Story 5 — Clean Uninstall (Priority: P2)

**Goal**: `specify extension remove subagent-flow` removes the extension's installed directory cleanly. The seven `.claude/agents/speckit-<phase>.md` DEPLOYED-copy files are deliberately left in place per Decision 6 Path 3 (they belong to the user's project after bootstrap; the orchestrator copied them there, not the installer). `--keep-config` is a no-op for this extension and is documented as such.

**Independent Test** (quickstart Steps 6 and 7): `specify extension remove subagent-flow` removes `.specify/extensions/subagent-flow/` entirely (manifest, scripts, README, and the seven SOURCE-copy agents under `agents/`); `specify extension list` no longer shows the extension; upstream commands still work; the seven `.claude/agents/speckit-*.md` DEPLOYED copies persist across the uninstall; re-running with `--keep-config` produces the same on-disk state as the default remove.

### Implementation for User Story 5

- [X] T022 [US5] Verify the manifest's uninstall behaviour is purely the default spec-kit `ExtensionManager.remove()` semantics: `/tmp/spec-kit/extensions/subagent-flow/extension.yml` MUST NOT contain a `hooks` block (no workflow-phase hooks, no after-anything entries — the manifest stays inert). Assert by parsing the YAML and confirming `hooks` is absent. Per Decision 6 Path 3, the deployed `.claude/agents/` files are not extension-owned post-bootstrap and require no removal hook; spec-kit's default `rmtree(.specify/extensions/subagent-flow/)` is the entire uninstall surface. This is the verification task that locks in the "no removal hook" choice — there is no conditional `hooks.after_remove` script in this task graph.
- [X] T023 [US5] Document the Path 3 uninstall contract in the README (T025 below) — default-remove deletes only `.specify/extensions/subagent-flow/`; the seven `.claude/agents/speckit-*.md` files persist as user-owned content; manual cleanup is the one-liner `rm .claude/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md`; `--keep-config` is a no-op for this extension and is documented as such. This task placeholder forces the README writer in T025 to include the matching snippet from quickstart Step 6/7. Implements FR-010 narratively.

**Checkpoint**: US5 is independently testable per quickstart Steps 6–7. The removal contract is "spec-kit's default `rmtree` plus deliberate persistence of the deployed copies"; no hook scripts are needed and none ship.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Two-hop deploy-lifecycle verification, user-facing documentation, fork-root cleanup (Decision 8), and end-to-end quickstart validation. The deploy-lifecycle checks (T024) are new under Path 3 — they replace the prior "auto-copy at install" verification, since the bootstrap runs at first invocation, not at install.

- [X] T024 [P] Verify the two-hop deploy lifecycle end-to-end against a fresh `specify init` project, per Decision 6 (Path 3) and Decision 9. Three sub-checks:
   (a) Post-install check (SOURCE copy populated, DEPLOYED copy untouched): after `specify extension add --dev /tmp/spec-kit/extensions/subagent-flow`, assert all seven files `.specify/extensions/subagent-flow/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md` exist via `test -f`. Assert `.claude/agents/speckit-*.md` MAY be empty/absent at this point — the installer does NOT auto-copy into `.claude/agents/`; that copy happens later via the orchestrator's inline bootstrap. No previous "auto-copy at install" check is performed.
   (b) Post-first-invocation check (DEPLOYED copy populated, content equality via `cmp -s`): after invoking `/speckit.subagent-flow.run` once in the AI agent, assert all seven files `.claude/agents/speckit-<phase>.md` exist; for each phase run `cmp -s .specify/extensions/subagent-flow/agents/speckit-$p.md .claude/agents/speckit-$p.md` and assert exit 0 (byte-equal). This proves the orchestrator's bootstrap (T012) deployed the SOURCE copies into the DEPLOYED location on first invocation. Implements quickstart Step 2 verification.
   (c) Post-uninstall persistence check: after `specify extension remove subagent-flow`, assert `.specify/extensions/subagent-flow/` is gone (`! test -d`) AND assert the seven `.claude/agents/speckit-*.md` files are still present (`test -f` for each). This proves Decision 6 Path 3 uninstall semantics: the SOURCE copies are removed by spec-kit's default `rmtree`; the DEPLOYED copies persist as user-owned content. Implements quickstart Step 6 verification.
- [X] T025 [P] Verify the bootstrap's three behaviours (FR-013 self-heal cases + the FR-013 source-missing error path), per quickstart Steps 4a/4b/4c. Three sub-checks against a fresh project where the extension has been installed AND `/speckit.subagent-flow.run` has been invoked once to populate `.claude/agents/`:
   (a) Self-heal — missing deployed copy: `rm .claude/agents/speckit-tasks.md`; invoke `/speckit.subagent-flow.run` again; assert no error is surfaced to the user, the orchestrator proceeds to Phase 1, AND `cmp -s .specify/extensions/subagent-flow/agents/speckit-tasks.md .claude/agents/speckit-tasks.md` exits 0 (the bootstrap restored the missing deployed copy from source). Implements quickstart Step 4a.
   (b) Self-heal — stale deployed copy: `echo "# tampered" > .claude/agents/speckit-plan.md`; invoke `/speckit.subagent-flow.run` again; assert no error is surfaced, the orchestrator proceeds to Phase 1, AND `cmp -s .specify/extensions/subagent-flow/agents/speckit-plan.md .claude/agents/speckit-plan.md` exits 0 (the bootstrap overwrote the tampered content with the source content). Implements quickstart Step 4b.
   (c) FR-013 source-missing error: `rm -rf .specify/extensions/subagent-flow/agents/`; invoke `/speckit.subagent-flow.run`; assert the orchestrator exits 1 BEFORE invoking any subagent (no `Agent` tool call appears in the trace), AND assert the error message contains all three literal elements: (i) at least one literal `.specify/extensions/subagent-flow/agents/speckit-<phase>.md` source path, (ii) the literal string `specify extension add subagent-flow`, (iii) the literal string `.specify/extensions/subagent-flow/README.md`. Then `specify extension add --dev /tmp/spec-kit/extensions/subagent-flow` to recover and re-invoke to confirm the bootstrap passes again. Implements quickstart Step 4c and FR-013's U1-pinned literal-element contract.
- [X] T026 [P] Run the maintainer CI workflow locally with `act` to verify constraint #1: `act workflow_dispatch -W /tmp/spec-kit/.github/workflows/subagent-flow-resync.yml --container-architecture linux/amd64`. Expect zero non-zero exits; if `templates/commands/*.md` has not drifted since T014, the `create-pull-request` step is a no-op. Implements quickstart Step 8.
- [X] T027 [P] Write `/tmp/spec-kit/extensions/subagent-flow/README.md` with the nine required sections from data-model.md §Entity: README — (1) What the extension does (one paragraph), (2) Install (`specify extension add subagent-flow`), (3) First-run experience (explanation that on first `/speckit.subagent-flow.run` invocation the orchestrator's inline bootstrap silently copies the seven baked agent files from `.specify/extensions/subagent-flow/agents/` into `.claude/agents/`; subsequent invocations are no-ops unless an extension upgrade has changed source content), (4) Use (`/speckit.subagent-flow.run` plus phase-by-phase summary), (5) Uninstall (`specify extension remove subagent-flow` default-remove leaves `.claude/agents/speckit-*.md` in place per Decision 6 Path 3; manual cleanup one-liner; `--keep-config` is a no-op — the T023 placeholder is consumed here), (6) Power-user regen (`bash .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh` only for "I customised local SKILLs"), (7) Compatibility (host needs `Agent` + `Skill` tools; spec-kit `>=0.2.0`), (8) Recovery (one-paragraph note explaining the only user-visible bootstrap error path: source dir missing → `specify extension add subagent-flow` to recover), (9) Maintainer section after `---` divider documenting the `act workflow_dispatch ...` invocation from T026. Implements FR-012 and SC-007.
- [X] T028 [P] Delete the fork-root duplicates per Decision 8: `rm /tmp/spec-kit/.claude/commands/speckit-flow.md`; `rm /tmp/spec-kit/.claude/agents/speckit-specify.md /tmp/spec-kit/.claude/agents/speckit-plan.md /tmp/spec-kit/.claude/agents/speckit-tasks.md /tmp/spec-kit/.claude/agents/speckit-analyze.md /tmp/spec-kit/.claude/agents/speckit-implement.md /tmp/spec-kit/.claude/agents/speckit-checklist.md /tmp/spec-kit/.claude/agents/speckit-taskstoissues.md`; `rm /tmp/spec-kit/scripts/bash/count-open-tasks.sh /tmp/spec-kit/scripts/bash/build-claude-agents.sh`. Do NOT touch `/tmp/spec-kit/templates/commands/*.md` — those are upstream-derived inputs, not duplicates.
- [X] T029 Run the full manual quickstart at `/tmp/spec-kit/specs/002-flow-extension-package/quickstart.md` Steps 0–9 end-to-end against a fresh `specify init` project. Record pass/fail per the "Pass/fail summary" table at the bottom of quickstart.md. All checkmarks across SC-001 through SC-007 must pass, including SC-002 (post-first-invocation the seven deployed copies content-match the sources) and SC-006 (extension upgrade refreshes deployed copies transparently on next invocation). This is the release gate.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: no dependencies; T001 must complete before T002–T004 (parent directory creation); T005 is independent.
- **Phase 2 (Foundational)**: depends on Phase 1; T006/T007 require T003; T008 requires T006 and T007; T009 requires T001 (and references the manifest skeleton in contracts/, no other deps).
- **Phase 3 (US1)**: depends on Phase 2. Within US1: T010 → T012 (same file, sequential); T011 and T013 are independent of T010/T012.
- **Phase 4 (US2)**: depends on Phase 2 (needs T007's copied generator and T004's `agents/` directory). T014 → T015 → T016 (sequential, same output dir). T017 is independent of T014–T016.
- **Phase 5 (US3)**: depends on Phase 2 (T006 helper) AND Phase 3 (T010/T012 orchestrator body). T018 requires both; T019 requires only T006.
- **Phase 6 (US4)**: depends on Phase 2 (T009 manifest) AND Phase 3 (T010 command file). T020 and T021 are independent.
- **Phase 7 (US5)**: depends on Phase 2 (T009 manifest). T022 is a manifest assertion; T023 is a documentation marker consumed by T027.
- **Phase 8 (Polish)**: T024 and T025 depend on Phases 1–7 being complete (they exercise the installed-and-invoked extension end-to-end against a fresh project). T026 depends on Phase 4 (T017 workflow file). T027 depends on T023 (and indirectly on all prior phases — README documents the whole system). T028 depends on Phases 1–7 being complete (the duplicates can only be safely deleted after the extension package fully replaces them). T029 is the final gate and depends on every prior task.

### User Story Dependencies

- **US1 (P1)**: depends only on Foundational. MVP slice.
- **US2 (P1)**: depends only on Foundational. Can run in parallel with US1.
- **US3 (P1)**: depends on Foundational + US1's T010/T012 (orchestrator body must exist and reference the helper path; the bootstrap edit must be in place because the body is treated as one finished artifact).
- **US4 (P2)**: depends on Foundational + US1's T010 (command file must exist to lint).
- **US5 (P2)**: depends on Foundational (manifest must exist to assert hooks-absence).

### Within Each User Story

- US1: T010 must precede T012 (same file). T011 and T013 are independent of T010/T012 and of each other.
- US2: T014 → T015 → T016 are strictly sequential (each reads the previous task's output). T017 is independent.
- US3: T018 and T019 are independent of each other.
- US4: T020 and T021 are independent of each other.
- US5: T022 and T023 are independent of each other; T023 is consumed by T027 in Phase 8.

### Parallel Opportunities

- **Phase 1**: T002, T003, T004, T005 run in parallel after T001.
- **Phase 2**: T006 and T007 run in parallel; T009 runs in parallel with T006/T007 (different file). T008 waits for T006 and T007.
- **Phase 3 (US1)**: T011 and T013 can run in parallel with T010 (different files); T012 must wait for T010.
- **Phase 4 (US2)**: T017 runs in parallel with T014–T016 (different files).
- **Across US1/US2**: After Phase 2 completes, US1 and US2 are entirely independent — different developers can work them simultaneously.
- **US3 within itself**: T018 and T019 are parallelisable.
- **US4 within itself**: T020 and T021 are parallelisable.
- **Polish**: T024, T025, T026, T027, T028 are parallelisable (different files / different verification targets); T029 is the final serial gate.

---

## Parallel Example: After Phase 2 Completes

```bash
# Developer A: drive US1 to completion
Task: "T010 Write commands/speckit.subagent-flow.run.md (verbatim copy + first two of three edits)"
Task: "T012 Insert inline bash bootstrap block at top of commands/speckit.subagent-flow.run.md"

# Developer B (in parallel): drive US2 to completion
Task: "T014 Generate the seven baked agent files into extensions/subagent-flow/agents/"
Task: "T015 Verify generator output (frontmatter, tools, header)"
Task: "T016 Verify idempotency (second-run diff is empty)"
Task: "T017 Write .github/workflows/subagent-flow-resync.yml"

# Developer C (in parallel): handle catalogue and validation
Task: "T011 Add subagent-flow entry to extensions/catalog.community.json"
Task: "T013 Parser-validate extensions/subagent-flow/extension.yml (no provides.agents, no hooks)"
```

---

## Implementation Strategy

### MVP First (US1 + US2 together)

Both US1 and US2 are P1 and both required for SC-001 (single-session zero-hand-edit install) and SC-002 (post-first-invocation the deployed copies content-match the sources). The MVP is "install works, sources are baked, orchestrator body contains the bootstrap, and the first invocation deploys to `.claude/agents/`". Sequence:

1. Phase 1 (Setup) — create directory skeleton.
2. Phase 2 (Foundational) — move scripts, write manifest (no `provides.agents`, no hooks).
3. Phase 3 (US1) + Phase 4 (US2) in parallel — orchestrator command (with inline bootstrap) + baked agent SOURCE copies.
4. **STOP and validate**: run quickstart Steps 0, 1, and 2. After Step 2, the bootstrap will have populated `.claude/agents/` transparently — verify with `cmp -s` against the source dir.
5. If green, the MVP is shippable as a dev-mode extension; the rest hardens it.

### Incremental Delivery After MVP

1. Add Phase 5 (US3) → run quickstart Step 3 → chunked loop works.
2. Add Phase 6 (US4) → run quickstart Step 5 → namespace clean.
3. Add Phase 7 (US5) → run quickstart Steps 6–7 → uninstall clean (extension dir gone, deployed copies persist).
4. Add Phase 8 (Polish) → run quickstart Steps 4a/4b/4c (bootstrap self-heal + FR-013 error), Step 8 (act), Step 9 (README usability) → release-ready.
5. After Phase 8 → T029 is the release gate.

### Parallel Team Strategy

With three developers:

- Day 1: Whole team completes Phase 1 + Phase 2 (a handful of small files).
- Day 2: Dev A on US1 (including the inline bootstrap edit in T012), Dev B on US2, Dev C on US4+US5 (manifest-adjacent work).
- Day 3: US3 (depends on US1, so Dev A or whoever finished US1 first picks it up).
- Day 4: Polish phase parallelised — T024/T025 (two-hop deploy lifecycle + bootstrap behaviours), T026 (act), T027 (README), T028 (fork-root cleanup). T029 last.

---

## Notes

- This feature ships zero compiled artifacts and zero automated tests. Verification is by `bash -n`, manifest-parser smoke checks, `cmp -s` content equality on the two-state agent-file lifecycle, and the manual quickstart. T029 is the release gate.
- The fork-root file deletion in T028 is intentionally LATE so that the duplicates remain available as live references while the extension payload is being authored. Do not delete them earlier.
- Path 3 lock-in (Decision 6 + Decision 9) means there is exactly one provisioning mechanism: the inline bash bootstrap in the orchestrator body (authored in T012). There is no `provides.agents` manifest field, no `defaults.agent_files` fallback, no install-lifecycle hook, no `hooks.after_remove` script, and no runtime "option-a vs option-b" detection. Any task or task language that implies otherwise is stale and must be rewritten to call this out.
- The orchestrator body produced by T010 + T012 is "verbatim with three edits" per plan.md §Summary; any divergence beyond those three edits violates Constitution Principle II (Verbatim Body, Rewritten Frontmatter) and is a release blocker. The bootstrap edit is the third edit and is scoped narrowly: ~10 lines at the very top of the body, no other body content touched.
- The bootstrap's three behaviours under T025 — self-heal missing deployed copy, self-heal stale deployed copy, FR-013 error when source dir is missing — are the runtime contract the orchestrator owns. The first two are silent (no user-visible output beyond optional one-line note); the third is the only user-visible error path under Path 3 and contains three pinned literal elements (missing source paths, recovery command verbatim, README path verbatim).
- Avoid: editing `templates/commands/*.md` (those are upstream-derived inputs); editing the seven baked agent files by hand (they are generator output — regenerate via T014 instead); registering any command other than `speckit.subagent-flow.run` (FR-009); adding any `hooks` block or `provides.agents` block to the manifest (Decision 6 Path 3 forbids both).
