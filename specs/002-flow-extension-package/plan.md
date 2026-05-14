# Implementation Plan: Subagent Orchestration as Installable Extension

**Branch**: `002-flow-extension-package` | **Date**: 2026-05-13 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-flow-extension-package/spec.md`

## Summary

Package the fork's subagent-orchestration delta (the `/speckit-flow` orchestrator command, the `build-claude-agents.sh` generator script, and the `count-open-tasks.sh` helper) as a self-contained spec-kit extension named `subagent-flow`. Downstream projects install it with `specify extension add subagent-flow` — no fork or hand-copy needed.

Two design pillars carried over from clarifications:

1. **Extension ID is `subagent-flow`** (Clarifications Q1) — explicit about the differentiating mechanic; commands take the form `speckit.subagent-flow.*`.
2. **Subagent files ship pre-baked and are deployed transparently by the orchestrator on first invocation** (Clarifications Q2 + Path 3 commitment) — the seven workflow agent files are generated at extension-release time against upstream and shipped as static payload inside the extension at `agents/`. The orchestrator's command body contains a small inline bash bootstrap that runs at its very top (before Phase 1 specify). The bootstrap iterates the seven phases and, for each one, copies the source file at `.specify/extensions/subagent-flow/agents/speckit-<phase>.md` into `.claude/agents/speckit-<phase>.md` if the deployed file is missing OR its content differs from the source (using `cmp -s` for content comparison). This single rule handles both fresh-install bootstrap and upgrade-drift refresh deterministically. The generator script still ships *inside* the extension as an internal maintenance tool for maintainer CI and for power users who customise their local SKILLs; ordinary end users never run it.

Concrete output: a new top-level directory `extensions/subagent-flow/` containing `extension.yml`, `commands/speckit.subagent-flow.run.md`, `scripts/bash/{count-open-tasks.sh,build-claude-agents.sh}`, pre-baked agent files (seven phases) under `extensions/subagent-flow/agents/`, a `README.md`, plus a maintainer-side GitHub Actions workflow that re-bakes those files when upstream `templates/commands/*.md` drifts. The orchestrator body is the existing `.claude/commands/speckit-flow.md` with three textual edits: namespace its description, rewrite the `count-open-tasks.sh` reference to `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh`, and insert a ~10-line inline bash bootstrap block at the very top of the body. The bootstrap loops over the seven phases (`specify plan tasks analyze implement checklist taskstoissues`); for each phase it uses `cmp -s` to compare `.specify/extensions/subagent-flow/agents/speckit-<phase>.md` against `.claude/agents/speckit-<phase>.md` and runs `cp` on miss. If the source dir itself is absent (interrupted install), the bootstrap exits 1 with a multiline error message containing (a) the literal list of missing source paths, (b) the recovery command `specify extension add subagent-flow`, and (c) the README path `.specify/extensions/subagent-flow/README.md`.

**I2 (manifest provisioning) is pre-decided in this plan**: the manifest does NOT declare `provides.agents` (no schema extension), and does NOT use any custom keys beyond schema 1.0. Subagent-file provisioning is handled entirely by the orchestrator's inline bootstrap step in its own command body — no spec-kit core changes, no manifest extension, no install-lifecycle hooks. Inspection of `src/specify_cli/extensions.py` confirms that (a) the validator silently accepts unknown keys under `provides`, so `provides.agents` would parse but be inert; (b) `ExtensionManager.install_from_directory()` only `shutil.copytree`s the extension into `.specify/extensions/<id>/` and registers commands — it has NO code path that interprets `provides.agents` and copies files outside the extension's own installed directory; (c) `ExtensionManager.remove()` only `rmtree`s the same directory; (d) `hooks` are workflow-phase hooks (`before_plan`, `after_specify`, …), not lifecycle hooks. Option (a) "ship a `provides.agents` block" and option (b-old) "ship install-lifecycle hooks" both require upstream changes to spec-kit core. Per the I2 directive "whichever option does NOT require upstreaming a schema change is the answer", **Path 3 — the orchestrator owns a transparent bootstrap step in its own command body** — is chosen. Spec-kit's `ExtensionManager.install_from_directory()` does only its standard `shutil.copytree`; the deployed copies under `.claude/agents/` are created by the orchestrator on first invocation. Uninstall (Decision 6 finalisation): spec-kit's default `extension remove` removes `.specify/extensions/subagent-flow/` cleanly; the deployed copies under `.claude/agents/` remain in place, since they are no longer owned by the extension's tracked payload after bootstrap. The README documents this as a deliberate behaviour: the user retains the upstream-derived content they need for their own `/speckit.<phase>` invocations and can manually delete the seven files if desired. The rejected options (a) and (b-old) are preserved in research.md Decision 6 for trail; the inline-bootstrap-in-orchestrator-body realisation is recorded in research.md Decision 9.

## Technical Context

**Language/Version**: Markdown (extension manifest, command file, README), YAML (manifest, GitHub Actions workflow), Bash 5 (both shipped scripts — already in use by the fork).
**Primary Dependencies**: spec-kit `>=0.2.0` (the version that finalised the extension system; matches the bundled `git` extension), the AI agent's `Agent` and `Skill` tools (Claude Code is the reference host). No new runtime deps on the user's machine — the existing spec-kit/Bash environment suffices (constraint #2).
**Storage**: Static files only. The extension's payload is shipped as a directory tree (or ZIP); installed copy lives under `.specify/extensions/subagent-flow/`. Pre-baked agent files are deployed to `.claude/agents/` by the orchestrator's inline bootstrap on its first invocation (NOT by the installer). No databases, no runtime state outside the orchestrator's existing per-feature `specs/<NNN-feature>/tasks.md` interaction (which is already disk-as-truth).
**Testing**: (a) `bash` syntax check (`bash -n`) on both shipped scripts; (b) extension self-install smoke test using `specify extension add --dev extensions/subagent-flow` against a fresh spec-kit project followed by manifest validation and presence checks on the seven agent files; (c) the maintainer-side CI sync workflow exercisable locally with `nektos/act` (constraint #1) — pinned to `act`-supported features, exposes a `workflow_dispatch` trigger, README documents the `act` invocation. End-to-end orchestrator behaviour reuses the manual quickstart from feature 001 (no automated test framework exists for the Markdown/Bash workflow).
**Target Platform**: Claude Code CLI on any OS where the existing fork already runs (Linux, macOS verified). Windows / PowerShell parity is explicitly out of scope for the initial release (spec Assumption "PowerShell parity is out of scope"); both shipped scripts are Bash-only. A future minor version can add `scripts/powershell/` siblings.
**Project Type**: Spec-kit extension package (Markdown + YAML manifest + Bash scripts + pre-baked Markdown agent files). Single deliverable; no source tree, no compile step. Builds entirely from text files.
**Performance Goals**: Install completes in the same envelope as the bundled `git` extension (copy ~15 small text files, register one command, write hook entries — well under a second on local disk). The orchestrator's per-sitting cost is unchanged from feature 001's baseline (one `Agent` call + one `Bash` read of `count-open-tasks.sh` per sitting).
**Constraints**:
- **act-compatible workflows** (constraint #1): The maintainer-side CI sync workflow MUST run locally under `nektos/act`. Pin to actions and runners `act` supports (no GitHub-hosted-only services), expose a `workflow_dispatch` trigger, and document the `act` invocation in the extension README's maintainer section.
- **No new runtime deps** (constraint #2): user-machine install adds nothing beyond Bash and the AI agent itself. The `requires.tools` block in `extension.yml` stays empty per FR-014; host-agent capability (the `Agent` tool for subagent delegation and the `Skill` tool for inline clarify) is documented narratively in the README, not declared in the manifest.
- **No spec-kit core changes** (I2 decision, Path 3): the manifest uses only schema 1.0 fields that the current `ExtensionManifest` validator and `ExtensionManager` installer/uninstaller in `src/specify_cli/extensions.py` already interpret. No `provides.agents` block, no install-lifecycle hooks, no custom keys. The orchestrator's inline bootstrap step (FR-013) is the sole subagent-file provisioning mechanism and runs in the orchestrator's own command body — entirely outside spec-kit core.
- **Constitution principles** (all five): the orchestrator still delegates only, edits nothing, treats disk as truth, isolates non-interactive phases in subagents, and keeps interactive phases (`clarify`) in-session. Repackaging changes the install vector, not the runtime contract.
- **Upstream compatibility**: the generator continues to consume upstream `templates/commands/*.md` verbatim and shells out only frontmatter rewrites — preserves merge-compat with `github/spec-kit`.
- **Namespace hygiene** (FR-009): the extension's single command name is `speckit.subagent-flow.run`; no upstream command is renamed, removed, or shadowed.
**Scale/Scope**: Single extension, one command, two scripts, seven pre-baked agent files. Roughly ~20 new tracked files; net code change is small because the orchestrator body and both scripts already exist in the fork — this feature relocates and namespaces them. README plus the maintainer workflow are genuinely new authoring.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Verdict | Justification |
|-----------|---------|---------------|
| I. Subagent Phase Isolation (NON-NEGOTIABLE) | Pass | Repackaging does not change the orchestrator's runtime behaviour: every non-interactive phase still runs in its own `Agent(subagent_type=speckit-<phase>)`. The pre-baked agent files are byte-for-byte equivalent to what the in-repo generator already produces, so subagent boundaries are preserved. |
| II. Verbatim Body, Rewritten Frontmatter | Pass — reinforced | The whole point of pre-baking is to keep the agent bodies a mechanical derivative of upstream `templates/commands/<phase>.md`. The generator is the *only* path to those bodies and it ships *inside* the extension so downstream power users can regenerate when they customise local SKILLs. The agent files carry the `AUTO-GENERATED` warning header and the README explicitly forbids hand-edits to them. The inline bootstrap added at the top of the orchestrator body is a guard — it does not modify any skill body content or rewrite agent frontmatter. |
| III. Interactive Phases Run In-Session | Pass | `clarify` and `constitution` remain in `SKIP_PHASES`. The orchestrator body still invokes clarify via the `Skill` tool inline and never invokes `constitution` (per-feature scope). Packaging does not introduce any new interactive phase. The bootstrap step does not prompt the user. |
| IV. Orchestrator Delegates, Never Edits | Pass | The packaged orchestrator command file is the existing `.claude/commands/speckit-flow.md` with three textual edits — a description rewrite, a script-path update, and the inline bootstrap block. None of those edits introduce direct authoring of spec/plan/tasks. The bootstrap writes to `.claude/agents/` only, which is neither spec, plan, nor tasks — those are the artifacts Principle IV protects from orchestrator authorship. The agent files are upstream-derived configuration assets, not per-feature artifacts. |
| V. Disk Is Truth | Pass — reinforced | The Phase 6 loop still terminates by re-reading `tasks.md` via `count-open-tasks.sh`. The script is being moved from `scripts/bash/` (fork repo) to `.specify/extensions/subagent-flow/scripts/bash/` (installed project), but its contract is unchanged. The inline bootstrap further reinforces this principle: it decides whether to copy each agent file by inspecting disk content via `cmp -s` against the source — disk content is the input to its decision. |

**All gates pass. No Complexity Tracking entries required.** Constitution version 1.1.1 referenced.

**Post-Phase-1 re-check (2026-05-13)**: Phase 0 and Phase 1 artifacts surfaced no design choice that weakens any gate. The data model treats every artifact as either generator-output or static manifest; nothing is authored by the orchestrator at install time.

**Post-analyze re-check (2026-05-14, after spec edits for C2/I1/U1 and I2 decision)**: The four issues from `/speckit-analyze` resolve as follows, with no gate impact:

- **C2 (Script-Path Assumption realigned with Decision 7)**: The spec's Assumptions block now states script paths are authored in installed form directly (no installer rewriting). This is the same approach the bundled `git` extension uses and aligns with Principle IV: the orchestrator's body is a static asset, not generated or rewritten at install time. **Gate impact: none.** Reinforces Principle II (verbatim body — no rewriting layer between authoring and installed form).
- **I1 (FR-014 weakened to speckit_version-only)**: The manifest declares only `requires.speckit_version`; host-agent capability is narrative in the README. Manifest content is purely declarative and matches what the existing `ExtensionManifest` validator interprets. **Gate impact: none.** Slightly reinforces Principle IV by removing a redundant gating mechanism that the installer would have ignored anyway.
- **U1 (FR-013 error contract pinned, Path 3 form)**: The orchestrator's inline bootstrap performs a content-aware copy that recovers automatically from missing or stale `.claude/agents/` files. The user-visible error only triggers if the source dir at `.specify/extensions/subagent-flow/agents/` is itself missing (interrupted install). That error contains three literal elements: the missing source paths, the recovery command `specify extension add subagent-flow`, and the README path. The check is read-only against disk content — Principle IV is preserved (the bootstrap writes only to `.claude/agents/`, never to spec/plan/tasks); Principle V is reinforced (the bootstrap's branch decision is derived entirely from disk content via `cmp -s`). **Gate impact: none.** Reinforces Principle V.
- **I2 (manifest provisioning, Path 3 chosen)**: No `provides.agents` schema field; no install-lifecycle hooks. The orchestrator's own command body owns the transparent bootstrap step. **Gate impact: none.** The bootstrap edits `.claude/agents/` only — that location is neither spec, plan, nor tasks, so Principle IV holds. The disk-content comparison via `cmp -s` reinforces Principle V. The bootstrap is a guard at the top of the orchestrator body and does not modify any skill body content, so Principle II is preserved.

**Post-Path-3-edit re-check (2026-05-14, after spec was rewritten to make the orchestrator own the transparent bootstrap)**: The bootstrap is a small new behaviour in the orchestrator body. Verifying gate-by-gate:

- **Principle II (Verbatim body, rewritten frontmatter)**: still holds. The body continues to function as the workflow controller; the bootstrap sits at the top of the body as a guard before Phase 1. No skill body content is modified by the bootstrap — it copies whole files from a source dir to a destination dir without reading their content beyond the byte-comparison `cmp -s` decision.
- **Principle IV (Orchestrator delegates, never edits)**: still holds. The protected artifacts (spec.md, plan.md, tasks.md) are untouched by the bootstrap. The bootstrap writes only to `.claude/agents/`, which are upstream-derived configuration assets, not per-feature artifacts the orchestrator is forbidden to author.
- **Principle V (Disk is truth)**: reinforced. The bootstrap's decision to copy or skip each file is derived entirely from disk content via `cmp -s`; there is no in-memory state, no cache, no flag file. Disk content alone determines whether a copy happens.

No gate downgrades; no new Complexity Tracking entries introduced.

## Project Structure

### Documentation (this feature)

```text
specs/002-flow-extension-package/
├── plan.md              # This file
├── spec.md              # Feature specification (already exists)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── extension-manifest.yml  # Phase 1 output: skeleton manifest (the only external interface)
├── checklists/          # (auto-generated by clarify; may be empty)
└── tasks.md             # Phase 2 output (/speckit-tasks command - NOT created here)
```

A `contracts/` directory exists because this feature *does* expose an external interface: the extension manifest itself. `extension.yml` is the only formal contract this package ships — every other artifact is a payload file (Markdown body, Bash script, or generated agent file) consumed exclusively by the manifest-driven install pipeline. The contracts/ entry is the canonical skeleton of that manifest.

### Source Code (repository root)

```text
extensions/
└── subagent-flow/                                # NEW: top-level extension package
    ├── extension.yml                             # Manifest (schema_version 1.0)
    ├── README.md                                 # User-facing docs (install/use/uninstall/regen)
    ├── commands/
    │   └── speckit.subagent-flow.run.md          # Orchestrator slash command body
    ├── scripts/
    │   └── bash/
    │       ├── count-open-tasks.sh               # MOVED from /scripts/bash/
    │       └── build-claude-agents.sh            # MOVED from /scripts/bash/ (internal tool)
    └── agents/                                   # Pre-baked subagent payload (seven files)
        ├── speckit-specify.md
        ├── speckit-plan.md
        ├── speckit-tasks.md
        ├── speckit-analyze.md
        ├── speckit-implement.md
        ├── speckit-checklist.md
        └── speckit-taskstoissues.md

extensions/catalog.community.json                 # EDITED: add subagent-flow entry

.github/workflows/
└── subagent-flow-resync.yml                      # NEW: maintainer-side scheduled regen workflow
                                                  # (workflow_dispatch + cron; act-compatible)

# REMOVED from this fork-level repo (now lives inside the extension):
#   scripts/bash/count-open-tasks.sh
#   scripts/bash/build-claude-agents.sh
#   .claude/commands/speckit-flow.md             # dev-only; replaced by the extension command
#   .claude/agents/speckit-*.md                  # dev-only; replaced by the baked payload
```

The seven pre-baked agent files live under the extension's own `agents/` directory (NOT directly in `.claude/agents/` inside the extension package). At install time, spec-kit's `ExtensionManager.install_from_directory()` recursively copies the entire `extensions/subagent-flow/` tree into the project's `.specify/extensions/subagent-flow/` — that is the only file motion the core installer performs. The seven baked agent files therefore land at `.specify/extensions/subagent-flow/agents/speckit-*.md`, NOT directly at `.claude/agents/speckit-*.md`. The orchestrator's inline bootstrap (FR-013) runs at its very top on every invocation and, for each phase, copies the source file to `.claude/agents/speckit-<phase>.md` if the deployed copy is missing or its content differs from the source. On first invocation this transparently populates `.claude/agents/`; on subsequent invocations the `cmp -s` content check makes the copy a no-op unless an extension upgrade has changed the source content. This is the Path 3 realisation of I2: the manifest itself declares no special handling for the agent files; the orchestrator's command body owns the entire provisioning lifecycle. Keeping the baked files at `extensions/subagent-flow/agents/` (no leading dot, no `.claude/` mirror inside the extension) prevents accidental "agent autoload" if a maintainer happens to symlink the extension into their own `.claude/` for dev testing.

The orchestrator command file body refers to its sibling helper script as `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` (the installed path), matching the existing convention from the bundled `git` extension (see `extensions/git/commands/speckit.git.commit.md`'s `.specify/extensions/git/scripts/bash/...` references). Per the spec's Assumption "Script paths are authored in installed form (per research.md Decision 7)", paths are written directly in the in-repo command body in their installed form — no installer-side rewriting. The in-repo `commands/speckit.subagent-flow.run.md` is byte-for-byte what spec-kit copies to `.specify/extensions/subagent-flow/commands/speckit.subagent-flow.run.md`. Only `count-open-tasks.sh` is extension-owned; the core spec-kit helper `check-prerequisites.sh` is referenced via its core installed path `.specify/scripts/bash/check-prerequisites.sh`, present in any spec-kit project by virtue of `specify init`.

**Structure Decision**: New top-level package directory `extensions/subagent-flow/` mirroring the existing `extensions/git/` layout. The fork's repo-root duplicates (`.claude/commands/speckit-flow.md`, `.claude/agents/speckit-*.md`, `scripts/bash/{count-open-tasks,build-claude-agents}.sh`) are removed in the same change so the fork has exactly one source of truth for the orchestration delta — inside the extension package. Maintainer CI re-bakes the agents on a schedule; downstream users install via `specify extension add`, then invoke `/speckit.subagent-flow.run` and the orchestrator's inline bootstrap transparently populates `.claude/agents/` on first run. No module/test-framework scaffolding needed: this is a Markdown/Bash deliverable. The Project Structure is unchanged by the Path 3 decision — the bootstrap lives entirely inside the orchestrator's command body, not in the directory layout.

## Complexity Tracking

*Not applicable.* All Constitution Check gates pass without justification needed.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| — | — | — |
