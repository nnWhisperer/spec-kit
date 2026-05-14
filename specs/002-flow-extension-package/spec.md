# Feature Specification: Subagent Orchestration as Installable Extension

**Feature Branch**: `002-flow-extension-package`

**Created**: 2026-05-13

**Status**: Draft

**Input**: User description: "Package the fork's subagent-orchestration changes (the `/speckit-flow` orchestrator command, the `build-claude-agents.sh` generator, and the `count-open-tasks.sh` helper) as a self-contained spec-kit extension that downstream projects can install via `specify extension add`."

## Clarifications

### Session 2026-05-13

- Q: Which ID should the packaged extension declare in its manifest? → A: `subagent-flow` (explicit about the differentiating mechanic; avoids collision with future "flow"-named extensions for unrelated concepts).
- Q: How are the `.claude/agents/speckit-*.md` subagent files made available to the user after install? → A: Pre-baked into the extension's payload (static files shipped alongside commands and scripts). Maintainer-side CI keeps them in sync against upstream spec-kit on a scheduled cadence. The generator script ships inside the extension as an internal/power-user maintenance tool, not exposed as a slash command.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install the Flow Extension Into a Fresh Spec-Kit Project (Priority: P1)

A developer who has installed upstream spec-kit (via `specify init`) wants to add the fork's per-feature orchestrator (`specify → clarify → plan → tasks → analyze → implement`, with chunked implement sittings) to their project without forking the upstream repository or hand-copying files.

**Why this priority**: This is the entire reason the extension exists. Without a working install path, none of the orchestration value reaches downstream users.

**Independent Test**: Run `specify extension add subagent-flow` against a clean spec-kit project, then verify the orchestrator command is registered, the pre-baked subagent files exist inside the extension's payload at `.specify/extensions/subagent-flow/agents/` (ready for first-invocation bootstrap into `.claude/agents/`), and the helper script is reachable from the orchestrator's body.

**Acceptance Scenarios**:

1. **Given** a project initialized with `specify init` (no fork modifications), **When** the user runs `specify extension add` for the flow extension, **Then** the extension is registered, its commands appear in `specify extension list`, and the orchestrator slash command is available in their AI agent.
2. **Given** the extension has been installed, **When** the user invokes the orchestrator slash command with a feature description, **Then** the orchestrator runs through all per-feature phases (specify, clarify, plan, tasks, optional analyze, implement) end-to-end, delegating non-interactive phases to isolated subagents and running clarify inline.
3. **Given** the extension is installed, **When** the user inspects their project, **Then** the helper that the orchestrator reads between implement sittings is present at a stable path that the orchestrator's body actually references.

---

### User Story 2 - Subagent Files Ship Pre-Baked and Are Available Immediately on Install (Priority: P1)

Downstream users do not run a code-generation step after install. The extension's payload includes `speckit-<phase>.md` agent files that were generated at extension-release time against the canonical upstream spec-kit sources. `specify extension add subagent-flow` deposits those files inside the extension's own payload at `.specify/extensions/subagent-flow/agents/`. On first orchestrator invocation, the orchestrator transparently copies them into `.claude/agents/` (via the FR-013 bootstrap step) so the `Agent(subagent_type=speckit-<phase>)` calls resolve correctly. From the user's perspective: install → invoke → it Just Works, no extra step. Keeping the baked files fresh against upstream is the extension maintainer's responsibility, handled via a scheduled CI workflow in the fork's repository.

**Why this priority**: The orchestrator depends on `Agent(subagent_type=speckit-<phase>)` resolving to files in `.claude/agents/`. Pre-baking removes the only credible install-time failure mode (generator didn't run) and matches every other bundled spec-kit extension, which ship 100% static payloads.

**Independent Test**: After `specify extension add subagent-flow` followed by exactly one orchestrator invocation, confirm that `.claude/agents/speckit-specify.md`, `.claude/agents/speckit-plan.md`, `.claude/agents/speckit-tasks.md`, `.claude/agents/speckit-analyze.md`, `.claude/agents/speckit-implement.md`, `.claude/agents/speckit-checklist.md`, and `.claude/agents/speckit-taskstoissues.md` exist and that their bodies match the upstream spec-kit skill bodies at the extension's release time. No generator command was run by the user; the orchestrator's bootstrap step did the copy transparently.

**Acceptance Scenarios**:

1. **Given** a fresh project with the extension just installed and the orchestrator invoked once, **When** the user lists `.claude/agents/`, **Then** the seven pre-baked subagent files are present (transparently copied by the orchestrator's bootstrap step from `.specify/extensions/subagent-flow/agents/`) and each carries the `AUTO-GENERATED` header naming the extension version that produced it.
2. **Given** the user has customized their local `.claude/skills/speckit-<phase>/SKILL.md` and wants the orchestrator to use that customized body, **When** they run `bash .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh` (documented in the extension README as a power-user step), **Then** the corresponding agent file is re-derived against the customized SKILL.
3. **Given** the maintainer's CI detects upstream skill drift and publishes a new extension version, **When** the downstream user re-runs `specify extension add subagent-flow` (or the equivalent upgrade command), **Then** `.claude/agents/` is updated to the new pre-baked bodies without any extra user action.

---

### User Story 3 - Chunked Implement Loop Works After Install (Priority: P1)

The orchestrator's Phase 6 reads `tasks.md` between subagent sittings via the helper script. After installation, the helper must be invocable from the orchestrator's body using a path that the orchestrator actually contains.

**Why this priority**: This is the differentiating feature of the fork. If the helper script is missing or its path in the orchestrator body does not match where the extension installer placed it, Phase 6 cannot terminate correctly and falls back to broken behavior.

**Independent Test**: On a feature whose `tasks.md` has more than one sitting's worth of work, observe that the orchestrator counts unchecked tasks between sittings, emits the progress note, and terminates when all tasks are checked off.

**Acceptance Scenarios**:

1. **Given** the extension is installed and the orchestrator is invoked on a feature with a long task list, **When** an implement sitting completes with unchecked tasks remaining, **Then** the orchestrator reads `tasks.md` from disk via the helper, emits a one-line progress note, and re-invokes the implement subagent without prompting the user.
2. **Given** all tasks become checked, **When** the orchestrator re-reads `tasks.md`, **Then** it exits the loop cleanly without an extra progress note.
3. **Given** a sitting returns with no on-disk progress (unchecked count did not drop), **When** the orchestrator detects this, **Then** it halts the loop and surfaces an "implementation incomplete" message with the remaining task count.

---

### User Story 4 - Extension Coexists With Upstream Per-Feature Commands (Priority: P2)

Downstream users already have `/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, etc. from upstream. The fork's orchestrator is *not* a replacement for those — it is an additional command that calls them as subagents. The extension must not collide with or overwrite upstream command names, configs, or scripts.

**Why this priority**: A namespace collision would degrade the user's existing workflow. Important, but a packaging-correctness concern rather than a feature-value concern.

**Independent Test**: Install the extension into a project that already has the full upstream command set. Confirm all upstream slash commands still work unchanged, and the new orchestrator command is namespaced under the extension's ID.

**Acceptance Scenarios**:

1. **Given** a project with upstream `/speckit.specify`, `/speckit.plan`, etc. registered, **When** the extension is installed, **Then** none of those upstream commands are renamed, removed, or rewritten.
2. **Given** the extension is installed, **When** the user lists registered commands, **Then** the orchestrator appears under the extension's namespace (`speckit.subagent-flow.*`) per the extension command-naming pattern.

---

### User Story 5 - Uninstall Is Clean (Priority: P2)

The user can remove the extension via `specify extension remove` without leaving orphan files behind that would break either upstream spec-kit or other extensions.

**Why this priority**: A reasonable expectation for any installable extension; not unique to this one but must be verified.

**Independent Test**: Install, then remove, then confirm: (a) the orchestrator command is no longer registered, (b) extension-owned files under `.specify/extensions/<ext-id>/` are gone, (c) generated `.claude/agents/speckit-<phase>.md` files are either left alone (since they describe upstream-owned content) or removed cleanly per project policy, (d) upstream commands still work.

**Acceptance Scenarios**:

1. **Given** the extension is installed, **When** the user runs `specify extension remove`, **Then** the orchestrator slash command is deregistered and the extension's owned files are removed.
2. **Given** uninstallation completes, **When** the user runs an upstream slash command like `/speckit.specify`, **Then** it works exactly as it did before the extension was installed.

---

### Edge Cases

- The user installs the extension twice (e.g., an upgrade or re-install after a version bump). The second install must overwrite cleanly: pre-baked agent files are re-copied, the orchestrator command is replaced (not duplicated), and no orphan files are left behind.
- The user has manually edited a file in `.claude/agents/` after install. The spec does not promise to preserve hand-edits — the files carry the `AUTO-GENERATED` header for that reason. A subsequent extension upgrade or re-install will overwrite the hand-edited file deterministically.
- The user has customized their local `.claude/skills/speckit-<phase>/SKILL.md` and wants the orchestrator to use that customized body. The extension README documents `bash .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh` as the regeneration command for this case; the customization escape hatch is not exposed as a slash command.
- The user manually deletes one or more `.claude/agents/speckit-*.md` files after install, then invokes the orchestrator. The orchestrator's bootstrap step (per FR-013) detects the missing deployed copies, restores them from `.specify/extensions/subagent-flow/agents/` automatically, and proceeds — the user observes no error. If the user also deleted the source files inside the extension's payload, FR-013 surfaces a clear error directing the user to re-install.
- The user invokes the orchestrator on a project where `tasks.md` is missing entirely for the current feature. Per the helper's existing contract, this reads as zero open tasks and the implement loop is skipped with an informative message.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The extension MUST be installable via `specify extension add` using both dev mode (local path) and (once published) catalog mode, with no manual file copying required.
- **FR-002**: The extension MUST declare a manifest (`extension.yml`) conforming to schema version `1.0` (the schema already used by the bundled `git` and `template` extensions), including required `extension`, `requires`, and `provides` blocks plus a `tags` array suitable for catalog discovery.
- **FR-003**: The extension MUST register the orchestrator as a single namespaced slash command following the extension naming pattern `speckit.{ext-id}.{cmd}` (so that it coexists with upstream's `/speckit.specify`, `/speckit.plan`, etc., without collision).
- **FR-004**: The extension's installed payload MUST include (a) pre-generated `speckit-<phase>.md` agent files (one per workflow phase) derived from upstream spec-kit's canonical SKILL/template bodies, shipped inside the extension's own payload directory at `.specify/extensions/subagent-flow/agents/`; (b) the open-task-count helper (`count-open-tasks.sh`) used by the orchestrator's Phase 6 loop; and (c) the generator script (`build-claude-agents.sh`) shipped as an internal/power-user maintenance tool — NOT exposed as a slash command. The spec-kit installer's `shutil.copytree` deposits the entire payload at `.specify/extensions/subagent-flow/` with no schema-driven side-effects. The transparent copy of the seven agent files into `.claude/agents/` is performed by the orchestrator's bootstrap step on first invocation (see FR-013); the user performs no install-time or post-install action.
- **FR-005**: After installation, the orchestrator's body MUST reference the helper script at the same path the installer actually placed it (i.e., the orchestrator-as-installed and the script-as-installed must agree). If installation rewrites script paths, the orchestrator body MUST use the rewritten form.
- **FR-006**: The generator MUST continue to auto-detect both the flat layout (`templates/commands/<phase>.md`) and the skill layout (`.claude/skills/speckit-<phase>/SKILL.md`), preferring `templates/commands/` when both exist, and MUST silently skip extension command skills (any skill folder whose name contains a hyphen after stripping the `speckit-` prefix).
- **FR-007**: The generator MUST exclude `clarify` and `constitution` from subagent generation (those phases run in-session as skills, not as subagents) and MUST set per-phase tool surfaces matching the existing fork behavior: `plan` gets WebFetch/WebSearch, `implement` gets TodoWrite, `analyze` and `taskstoissues` get read-only surfaces, and all other phases get the default surface.
- **FR-008**: The orchestrator command, when invoked, MUST orchestrate the per-feature sequence (`specify → clarify → plan → tasks → optional analyze → implement`) exactly as the fork's current `/speckit-flow` does, including (a) delegating non-interactive phases to isolated subagents via the `Agent` tool, (b) invoking `clarify` inline via the `Skill` tool, (c) running the Phase 6 chunked-sitting loop with disk-as-truth termination via the helper script, and (d) auto-accepting each sitting's pacing without asking the user "should I continue?".
- **FR-009**: The extension MUST NOT modify, rename, or shadow any upstream-shipped command (`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, `/speckit.clarify`, `/speckit.analyze`, `/speckit.implement`, `/speckit.checklist`, `/speckit.taskstoissues`, `/speckit.constitution`). The orchestrator delegates to those — it does not replace them.
- **FR-010**: The extension MUST be removable via `specify extension remove` with no residual registration of its commands and no breakage of upstream commands or other installed extensions.
- **FR-011**: The extension's installed payload MUST be reproducible: running the generator a second time against an unchanged source layout MUST produce byte-identical (or semantically-identical) agent files to the first run, modulo timestamps if any are embedded.
- **FR-012**: The extension's documentation (README) MUST tell users (a) what the orchestrator does in one paragraph, (b) the exact install command, (c) when (and how) the bundled generator script may be re-run manually — limited to the power-user case of "I customized my local SKILLs and want the agents re-derived against them" — and (d) how to remove the extension. The README MUST NOT instruct ordinary users to run the generator as part of routine install/upgrade.
- **FR-013**: Before any subagent invocation in Phase 1, the orchestrator MUST perform a bootstrap-or-fail check. For each of the seven required agent files (`.claude/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md`): (1) if the deployed copy is missing OR its content differs from the source copy at `.specify/extensions/subagent-flow/agents/speckit-<phase>.md`, the orchestrator MUST silently copy the source file into the deployed location (this transparently handles both fresh-install bootstrap and upgrade-drift refresh); (2) if the source file at `.specify/extensions/subagent-flow/agents/` is itself missing, the orchestrator MUST exit with an error message containing (a) the literal list of missing source paths, (b) the recovery command `specify extension add subagent-flow` (re-install), and (c) the README path (`.specify/extensions/subagent-flow/README.md`), and MUST NOT invoke any subagent. The bootstrap step MUST NOT prompt the user or log non-error output beyond a single optional one-line note when files were copied.
- **FR-014**: The extension MUST declare its minimum compatible spec-kit version in the `requires.speckit_version` field of `extension.yml`, so that `specify extension add` can refuse to install against an out-of-date host. AI-agent capabilities (the `Agent` tool for subagent delegation and the `Skill` tool for inline clarify) are documented narratively in the README — the manifest schema's `requires.tools` block is reserved for MCP/CLI tooling and is left empty by this extension. Install does not gate on host-agent capability; a user running on a host that lacks `Agent`/`Skill` will see the failure surface at orchestrator-invocation time, not at install.

### Key Entities *(include if feature involves data)*

- **Extension Manifest** (`extension.yml`): The declarative root of the package. Names the extension, lists its commands and their files, declares hooks (if any), and states compatibility requirements. Consumed by `specify extension add` at install time and by `specify extension list` afterwards.
- **Orchestrator Command File** (`commands/speckit.subagent-flow.run.md`): The Markdown body of the orchestrator slash command. Same content as the fork's current `.claude/commands/speckit-flow.md` but with frontmatter and any in-body script-path references adjusted for the namespaced installed form.
- **Generator Script** (`scripts/bash/build-claude-agents.sh`): Internal maintenance tool. Primary consumer is the maintainer's CI workflow that bakes `.claude/agents/speckit-*.md` files against upstream spec-kit for each extension release. Also available to downstream power users who customize their local SKILLs (invoked manually as bash; not exposed as a slash command). Reads phase content from a project's source layout (skill or flat), writes one subagent file per workflow phase to `.claude/agents/`. Idempotent. Skips `clarify` and `constitution`. Skips extension command skills.
- **Open-Task Helper** (`scripts/bash/count-open-tasks.sh`): Tiny disk-reader used by the orchestrator's Phase 6 loop. Given a `tasks.md` path, prints the integer count of `- [ ]` lines (treating a missing file as zero).
- **Pre-Baked Subagent File** (`.claude/agents/speckit-<phase>.md`, shipped inside the extension and copied into the project at install): One per workflow phase. Generated at extension-build time by the maintainer's CI; not re-generated on the user's machine at install. Frontmatter assigns the agent name, description (copied from the source's `description:`), and tool surface (per-phase). Body is copied verbatim from the source. Carries an `AUTO-GENERATED` warning header.
- **Catalog Entry** (in `extensions/catalog.json` or `catalog.community.json`): The discovery record that lets a user `specify extension add` by ID without knowing the underlying repository URL. Optional for dev-mode install but required for "official" distribution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer with a fresh spec-kit project can install the extension and run the orchestrator end-to-end on a new feature description in a single session, with zero hand-edits to files inside `.specify/` or `.claude/` between install and first use.
- **SC-002**: After install and one orchestrator invocation (which performs the transparent bootstrap), the seven pre-baked subagent files (`speckit-specify`, `speckit-plan`, `speckit-tasks`, `speckit-analyze`, `speckit-implement`, `speckit-checklist`, `speckit-taskstoissues`) all exist under `.claude/agents/`, all carry the `AUTO-GENERATED` header, and all have bodies that match the upstream spec-kit SKILL or template content at the extension's release time.
- **SC-003**: The orchestrator's Phase 6 loop, when run on a feature whose initial `tasks.md` has at least twice as many open tasks as one subagent sitting can plausibly close, executes more than one sitting, reads the helper between every sitting, and terminates when and only when the helper reports zero open tasks.
- **SC-004**: Uninstall via `specify extension remove` followed by `specify extension list` shows the extension is gone, and a subsequent invocation of any upstream slash command (e.g., `/speckit.specify`) still works without error.
- **SC-005**: Re-installing the extension over an existing install does not duplicate or corrupt the orchestrator command — `specify extension list` continues to show exactly one registration for it.
- **SC-006**: After a new extension release that incorporates upstream spec-kit updates (produced by the maintainer's CI sync), a downstream user who runs `specify extension add subagent-flow` (re-install or upgrade) and then invokes the orchestrator once sees `.claude/agents/speckit-*.md` in their project change to match the new upstream content — the orchestrator's bootstrap step detects content drift between the installed source files (under `.specify/extensions/subagent-flow/agents/`) and the deployed copies (under `.claude/agents/`) and refreshes the latter automatically. No user-initiated generator step.
- **SC-007**: The extension's README is sufficient for a user who has never seen the fork to install, invoke, and uninstall the extension correctly on first read — no other repository file needs to be consulted.

## Assumptions

- **Extension ID** is `subagent-flow` (per Clarifications Q1), yielding command names of the form `speckit.subagent-flow.*`. The fork's current development-only slash command `/speckit-flow` becomes `/speckit.subagent-flow.run` once packaged. The shorter alternative `flow` was rejected as too generic.
- **Agent file provisioning model** (per Clarifications Q2): Agent files are pre-baked at extension-release time. The extension's CI runs the generator against upstream spec-kit periodically (cadence is a maintainer-controlled concern, not a user contract) and commits any drift back to the fork. End users perform no install-time or post-install generation step. The generator script ships inside the extension as `scripts/bash/build-claude-agents.sh` for downstream power users who customize their local SKILLs and want to re-derive the agent bodies; it is not exposed as a slash command.
- **CI sync workflow** (maintainer-side, not part of the extension's user-facing contract): The fork's repository runs a scheduled GitHub Actions workflow that fetches upstream spec-kit, runs the generator against the upstream sources, and commits any changes to the baked `.claude/agents/speckit-*.md` files inside the extension's payload directory. The cadence (e.g., daily) is a maintainer decision; the user contract is only "the most recent extension release ships agent bodies derived from the upstream content available at the time of release".
- **Script paths are authored in installed form** (per research.md Decision 7): Script paths inside the orchestrator's command body are written directly in their installed form — `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` for the extension-owned helper and `.specify/scripts/bash/check-prerequisites.sh` for the core spec-kit helper. The spec-kit extension installer does **not** rewrite paths at install time; the in-repo command file is byte-for-byte what lands at `.claude/commands/speckit.subagent-flow.run.md`. Only `count-open-tasks.sh` is extension-owned; `check-prerequisites.sh` is a core spec-kit script already present in installed projects.
- **Target host environment**: The extension targets spec-kit `>=0.2.0` (the version where the extension system was finalized; matches the existing `git` extension's declared minimum) and assumes the AI agent supports both the `Agent` tool (for subagent delegation) and the `Skill` tool (for inline clarify). Claude Code is the reference host; other agents are out of scope for the initial release.
- **Skill layout dominance**: At extension-build time (in the maintainer's CI), the generator runs against the spec-kit dev repo's `templates/commands/<phase>.md` (flat) layout to produce canonical agent bodies. The generator's auto-detection of `.claude/skills/speckit-<phase>/SKILL.md` (skill layout) remains in place so that downstream power users invoking the generator manually against their installed project also work correctly.
- **PowerShell parity is out of scope for the initial release**: Both shipped scripts are Bash-only. A `scripts/powershell/` counterpart can be added later without changing the extension's command surface; the Bash-only constraint is inherited from the fork's current state.
- **No external tools required**: The extension does not depend on any MCP server or third-party CLI beyond Bash and the AI agent itself. The `requires.tools` block is therefore empty.
- **No configuration file required**: The extension's behavior is fully determined by its commands' arguments and the project's existing layout. No `config-template.yml` is shipped (unlike the `git` extension, which configures branch numbering); if a future need arises, it can be added in a minor version bump.
