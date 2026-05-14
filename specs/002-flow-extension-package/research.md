# Phase 0 Research: Subagent Orchestration as Installable Extension

**Feature**: 002-flow-extension-package
**Date**: 2026-05-13

This document resolves every NEEDS CLARIFICATION in `plan.md` (none remained after the clarify pass) and records the design decisions that shape Phase 1's artifacts.

---

## Decision 1: Manifest schema and namespace

**Decision**: Use `schema_version: "1.0"` with extension ID `subagent-flow`. The single registered command is `speckit.subagent-flow.run`. `requires.speckit_version` is `>=0.2.0`; `requires.tools` is empty.

**Rationale**:
- `1.0` is the schema in use by the bundled `git` and `template` extensions; downstream catalogue tooling already validates against it. Inventing a new schema version would force a CLI/parser update that adds zero user value. Per Decision 6, this extension uses only fields the existing schema 1.0 validator already interprets — no `provides.agents`, no new top-level keys.
- `subagent-flow` was selected in Clarifications Q1 over the shorter alternative `flow` precisely because future extensions may want the `flow` namespace for unrelated concepts (e.g., generic workflow visualisation). The differentiating mechanic of *this* extension is the subagent-per-phase delegation; the ID names that mechanic.
- The single-word command name `run` keeps the slash command short (`/speckit.subagent-flow.run`) and matches user mental-model "run the flow". `start` and `orchestrate` were rejected for being longer without disambiguating.
- The minimum spec-kit version `>=0.2.0` is the version where the extension system was finalised. Lower versions reject the manifest at install — the right failure mode.
- `requires.tools` is empty per FR-014: the extension calls no MCP servers and no third-party CLIs. It uses Bash (always available on Claude Code hosts) and the agent's own `Agent` and `Skill` tools, whose capability is documented narratively in the README (see Decision 4) — not declared in the manifest, because the manifest schema's `requires.tools` is for MCP/CLI discovery, not host-agent capabilities.

**Alternatives considered**:
- Extension ID `flow`: rejected per spec Clarifications Q1.
- Multiple registered commands (e.g., `speckit.subagent-flow.run`, `speckit.subagent-flow.regenerate`): rejected. Exposing the generator as a slash command would invite ordinary users to run it as part of routine work, defeating the "pre-baked, no end-user generation step" contract from Clarifications Q2.
- Higher minimum (`>=0.3.0`): rejected — no API surface used by this extension was added after 0.2.0; raising it would gratuitously cut off users.

---

## Decision 2: Pre-baked agent file provisioning

**Decision**: Ship the seven workflow-phase agent files (`speckit-specify`, `speckit-plan`, `speckit-tasks`, `speckit-analyze`, `speckit-implement`, `speckit-checklist`, `speckit-taskstoissues`) as static `.md` files inside the extension under `agents/`. At install time, copy them into the user's `.claude/agents/` directory. End users perform no generation step.

**Rationale**:
- This is the explicit outcome of Clarifications Q2. The two rejected alternatives — running the generator on first orchestrator invocation, or registering it as a post-install hook — both reintroduced a credible install-time failure mode (generator didn't run, generator crashed, generator wrote partial output) that pre-baking eliminates.
- Pre-baking matches every other bundled spec-kit extension. The `git` extension ships 100% static payload; the `template` extension is 100% static. Consistency reduces surprise and makes the install pipeline simpler — the installer is already a recursive copy.
- The `AUTO-GENERATED` header in each baked file (kept identical to the generator's existing output) advertises that hand-edits will be lost on the next install/upgrade.

**Alternatives considered**:
- Run generator at first orchestrator invocation: rejected (Clarifications Q2 explicitly). Adds a runtime dependency on Bash being usable from the orchestrator's body just to bootstrap, increases first-run latency, and conflates "install" with "first use".
- Run generator as a post-install hook: rejected. Hooks are user-visible in the install output and confuse the "this extension is fully static" mental model. Also fails opaquely if the generator's source-detection picks the wrong layout.
- Skip pre-baking and rely on the user running `bash .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh` after install: rejected. This is the *power-user escape hatch*, not the default flow; making it mandatory would block the SC-001 "single-session zero-hand-edit" success criterion.

---

## Decision 3: Where the agent files live inside the extension payload

**Decision**: Store the pre-baked agent files at `extensions/subagent-flow/agents/speckit-<phase>.md` (i.e., directly under the extension root, NOT inside a nested `.claude/agents/` mirror). The orchestrator command file's `## Prerequisites` section documents `.claude/agents/` as the *project*-side destination.

**Rationale**:
- Keeping a `.claude/agents/` directory *inside* the extension package would be misleading: a maintainer dev-testing the extension via symlink could accidentally see those files autoloaded by their own Claude Code session. Putting them under `agents/` (no leading dot) makes it obvious that they are *payload to be copied*, not *active agent files*.
- The installer treats them as ordinary files — copies them on install, removes them on uninstall (Decision 6). No special handling is needed.
- The `commands/speckit.subagent-flow.run.md` body documents the *project-side* path (`.claude/agents/`) because that is what the user sees and what FR-013's error message points at.

**Alternatives considered**:
- `extensions/subagent-flow/.claude/agents/`: rejected for the symlink-autoload hazard above and because no other bundled extension uses a leading-dot payload directory.
- `extensions/subagent-flow/payload/agents/`: rejected as gratuitously nested. `agents/` is unambiguous enough.

---

## Decision 4: Compatibility declaration (FR-014)

**Decision**: Declare `requires.speckit_version: ">=0.2.0"` in `extension.yml` and leave `requires.tools` empty. Host-agent capability (the `Agent` tool for subagent delegation and the `Skill` tool for inline clarify) is documented narratively in the README, NOT declared in the manifest. This matches FR-014 verbatim after the analyze pass: the manifest schema's `requires.tools` block is reserved for MCP/CLI tooling, and host-agent capability is a README concern.

**Rationale**:
- The schema's `requires.tools` field expects entries like `{name: <tool>, required: true|false}` matched against MCP server and CLI tool discovery — not against the host agent's intrinsic capability surface. Putting `Agent` or `Skill` there would parse without error (the validator does not enforce a controlled vocabulary on tool names) but would be wholly cosmetic: nothing in `ExtensionManager` queries the host AI agent for its tool surface. Install does not gate on host capability; the gate appears at orchestrator-invocation time, where a host that lacks `Agent` or `Skill` will fail in the orchestrator's body itself.
- This matches the bundled `git` extension's pattern (`requires.tools: [{name: git, required: false}]` — a CLI, not an AI capability). FR-014's narrative-only stance for AI capabilities is intentional: a manifest declaration would imply a check that does not exist.
- `>=0.2.0` is the same floor the bundled `git` extension declares — the version the extension system itself was finalised in. Going lower would risk installing into a host where manifests are parsed differently. Going higher would gratuitously cut off users for no API gain.
- README documents host-agent capability under a "Compatibility" section: "Claude Code is the reference host; agents that lack the `Agent` tool for subagent delegation and the `Skill` tool for inline clarify cannot run the orchestrator end-to-end. Install does not gate on this — the failure surfaces at the first `/speckit.subagent-flow.run` invocation."

**Alternatives considered**:
- `requires.tools: [{name: "Agent", required: true}, {name: "Skill", required: true}]`: rejected. The installer would not actually check host-agent capability at install — the field is matched against MCP/CLI discovery only. Declaring it would mislead future maintainers into thinking install gates on Agent/Skill availability when it does not.
- Bumping `speckit_version` floor to `>=0.3.0` or higher: rejected per Decision 1 — no required API was added after 0.2.0.
- No version floor at all: rejected. The validator enforces `speckit_version` presence; "use the latest" implicit defaults are a footgun.

---

## Decision 5: Maintainer-side CI sync workflow (act-compatible)

**Decision**: Ship `.github/workflows/subagent-flow-resync.yml` in the fork's main repo (not inside the extension package, since this is maintainer infrastructure, not user-facing). The workflow:

1. Triggers on `workflow_dispatch` (manual, the only reliable trigger under `act`) and `schedule` (cron, used by GitHub but ignored by `act`).
2. Runs on `ubuntu-latest` (the runner `act` defaults to and most reliably supports).
3. Steps:
   - `actions/checkout@v4` — pinned to a version `act` is known to support.
   - Run `bash extensions/subagent-flow/scripts/bash/build-claude-agents.sh` with `SRC_DIR=templates/commands` and `OUT_DIR=extensions/subagent-flow/agents`.
   - Detect changes via `git diff --quiet` on the agents/ subtree.
   - If changes exist, commit them via the standard `peter-evans/create-pull-request@v6` action (act-compatible when run with `--container-architecture linux/amd64`) so the maintainer reviews drift via PR rather than direct-to-main push.

The README's maintainer section documents the local-verification command:

```bash
act workflow_dispatch -W .github/workflows/subagent-flow-resync.yml --container-architecture linux/amd64
```

**Rationale**:
- Constraint #1 explicitly requires `act` compatibility. The two settings that historically break `act` are (a) GitHub-only triggers like `pull_request_target` and (b) GitHub-only runners. The workflow uses neither.
- `workflow_dispatch` is the trigger that works identically under `act` and on GitHub — making it the primary trigger lets the maintainer run a one-off resync the same way locally and remotely. `schedule` is added for hands-off operation but is ignored by `act`; not a problem for local verification because the maintainer can always force a `workflow_dispatch` run.
- Opening a PR (rather than committing directly) gives the maintainer a chance to review whether upstream drift is intentional before agent bodies change. This is consistent with the constitution's "regenerate instead of hand-edit" rule.
- Pinning the actions to versions `act` is known to support avoids the silent-breakage pattern where a `@latest`-style reference picks up a new container image that `act` doesn't yet wrap.

**Alternatives considered**:
- Commit-direct-to-main instead of opening a PR: rejected. Drift in `templates/commands/*.md` from upstream merges can sometimes be intentional and require human review (e.g., to update `SKIP_PHASES` if a new phase appears). PR gating preserves that review point.
- Run the workflow on every push to main rather than on a schedule: rejected. Most pushes do not touch upstream-derived files; the workflow would run too often and add noise.
- Skip the CI workflow entirely and rely on the maintainer running the generator manually: rejected. The user contract from Clarifications Q2 ("the most recent extension release ships agent bodies derived from the upstream content available at the time of release") requires a reliable, repeatable bake step. Manual is unreliable.

---

## Decision 6: Subagent-file provisioning and uninstall semantics (resolves I2 deterministically — Path 3)

**Decision** (pre-decided at release time, not deferred to install-time detection): The extension does NOT declare any manifest field beyond schema 1.0 to describe its baked agent payload. No `provides.agents` block; no `defaults.agent_files` list; no install-lifecycle hooks. Subagent-file provisioning is handled entirely by the orchestrator's own command body — a small inline bash bootstrap block at the top of `commands/speckit.subagent-flow.run.md` performs `shutil.copytree`-equivalent file motion from `.specify/extensions/subagent-flow/agents/speckit-<phase>.md` to `.claude/agents/speckit-<phase>.md` for each phase, gated by a `cmp -s` content check (copy on miss-or-differ; no-op on match). The installer's job is purely `shutil.copytree` of the extension into `.specify/extensions/<id>/`; the bootstrap, executed at first invocation, takes care of the rest.

**Uninstall semantics**: `specify extension remove subagent-flow` removes `.specify/extensions/subagent-flow/` cleanly (standard spec-kit behaviour). The seven `.claude/agents/speckit-<phase>.md` files are deliberately LEFT IN PLACE. This is the natural consequence of Path 3: once the bootstrap has copied a file to `.claude/agents/`, that file is no longer owned by the extension's tracked payload — it is part of the user's project, where it persists across `extension remove` so the user retains the upstream-derived content they need for their own `/speckit.<phase>` invocations. The README documents this as a deliberate behaviour and offers the one-line `rm .claude/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md` for users who want to scrub them manually. The `--keep-config` flag is a no-op for this extension and is documented as such.

**Rationale** (Path 3 commitment, with options (a) and (b-old) preserved as rejected):

The /speckit-analyze pass surfaced I2 as the "schema-extension fork" — the prior research entry proposed two implementation paths and deferred the choice to install-time detection (T012). I2 mandates a release-time pre-decision; the directive is "whichever option does NOT require upstreaming a schema change to spec-kit is the answer." Investigation of the current `src/specify_cli/extensions.py` produced these facts:

1. **The validator silently accepts unknown keys.** `ExtensionManifest._validate()` checks REQUIRED_FIELDS at the top level, then iterates only `provides.commands` and `hooks`. An unknown `provides.agents` block parses without error or warning. So adding `provides.agents` is not technically a "schema change" at the validator level — it's a no-op for parsing.
2. **The installer ignores `provides.agents`.** `ExtensionManager.install_from_directory()` does exactly two file-motion operations: `shutil.copytree(source_dir, .specify/extensions/<id>/, ignore=ignore_fn)` and the `CommandRegistrar` linking of `provides.commands[].file` into `.claude/commands/`. There is no code path that interprets a `provides.agents` block. Adding the block would require new code in the installer.
3. **The uninstaller mirrors the installer.** `ExtensionManager.remove()` calls `shutil.rmtree(extension_dir)`, unregisters slash commands, removes hook entries from `.specify/extensions.yml`, and removes the registry entry. It has no code path that interprets `provides.agents` to delete files outside `.specify/extensions/<id>/`.
4. **Hooks are workflow-phase events, not lifecycle events.** The `hooks` block in the manifest registers entries like `before_plan` and `after_specify`, whose `command:` field references a registered slash command. There is no `after_install` / `before_remove` event in the current code; nothing fires Bash scripts on install or uninstall. Adding install-lifecycle hooks would require new code in the installer AND a new manifest schema field.

Conclusion: **option (a) requires both a schema-validator extension AND new installer code** in spec-kit core to consume the new field. **Option (b-old) as originally framed — "install/remove hooks owned by the extension" — also requires new installer-lifecycle hook events in spec-kit core**, because no such events exist today. *Both* require upstream changes. The deterministic answer that requires zero spec-kit core changes is **Path 3: the orchestrator owns a transparent bootstrap step in its own command body**. The seven baked agent files ship inside the extension at `extensions/subagent-flow/agents/`; spec-kit's installer copies the whole directory into `.specify/extensions/subagent-flow/`; on first invocation, the orchestrator's inline bootstrap iterates the seven phases and copies any file that is missing or out-of-date in `.claude/agents/`. No core changes; no schema extension; no NEW manifest keys; no user-visible "you must run this command" step under the happy path.

This is the Path 3 finalisation, locked in at release time. It is not a "runtime detection" choice — it does not depend on any property of the install target. Whatever spec-kit version a user has, this extension behaves identically because it touches no manifest field the validator doesn't already accept.

Uninstall semantics follow from the same architecture. Spec-kit's default uninstall removes only `.specify/extensions/subagent-flow/`. The deployed copies at `.claude/agents/` were created by the orchestrator (not by the installer) and were never part of the extension's tracked payload after bootstrap, so they persist across `extension remove`. This is documented in the README as a deliberate behaviour: the user keeps the upstream-derived content for their own `/speckit.<phase>` invocations (and can manually delete the files if undesired). It is *not* a workaround for a missing core feature — it is the consequence of the chosen architecture, and the design treats it as a feature, not a bug.

**Rejected option (a)** — schema-extended `provides.agents` block: rejected because consuming it requires upstreaming code into `ExtensionManager.install_from_directory()` (to copy `agents/*.md` into `.claude/agents/` on install) and into `ExtensionManager.remove()` (to delete them on uninstall, gated by `--keep-config`). The current `src/specify_cli/extensions.py` accepts the field at parse time but does nothing with it. Shipping the field today would mislead future maintainers into thinking the install-time copy works automatically when in fact it does not. Even though no schema version bump would be needed (the validator accepts unknown keys), this option is rejected on the literal reading of the I2 directive ("does NOT require upstreaming") — option (a)'s installer support has to come from somewhere, and that somewhere is spec-kit core.

**Rejected option (b-old)** — `defaults.agent_files` list + install/remove hooks owned by the extension: rejected because `hooks` in the current schema are workflow-phase hooks (fire when a slash command runs), not install-lifecycle hooks (fire when `extension add`/`remove` runs). There is no extension-owned mechanism today that fires Bash scripts at install or uninstall. This option also requires core changes; same disqualification.

**Rejected option (b-intermediate)** — orchestrator's Phase 0 preflight surfaces a friendly error pointing at `bash .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh` and exits without invoking any subagent, requiring the user to run the regen command before re-invoking the orchestrator: rejected because it imposes a user-visible install-time step that contradicts SC-001's "zero-hand-edit, single-session" promise. The bootstrap-in-orchestrator-body approach (Path 3) achieves the same effect without any user-visible friction: the orchestrator self-heals on first invocation, and the user never sees the prompt-to-run-regen-command unless the install itself is corrupted (source dir missing).

**The chosen path (Path 3)** — orchestrator-body-driven transparent bootstrap — has the additional benefit that it works identically regardless of whether the user installs via dev-mode (`--dev`), catalog mode, or ZIP. The provisioning gate is the orchestrator's first invocation, and it self-recovers from many common failure modes: a user manually deleting an agent file gets it transparently restored; an extension upgrade that changes agent bodies gets its new content transparently propagated; an interrupted install (source dir missing) surfaces a clean error pointing at re-install.

The README documents the lifecycle:

```
specify extension add subagent-flow
# Then in your AI agent:
/speckit.subagent-flow.run "<feature description>"
# On first invocation, the orchestrator's inline bootstrap silently copies
# the seven agent files from the extension's payload into .claude/agents/.
# The user sees no extra prompt — the orchestrator proceeds straight to Phase 1.

# To uninstall:
specify extension remove subagent-flow
# The extension dir under .specify/extensions/subagent-flow/ is removed.
# The seven .claude/agents/speckit-*.md files are deliberately left in place
# so the user retains the upstream-derived content for their own
# /speckit.<phase> invocations. To remove them manually:
rm .claude/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md
```

---

## Decision 7: Script-path references inside the orchestrator command body (FR-005, spec C2 realignment)

**Decision**: Write `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` (extension-owned helper) and `.specify/scripts/bash/check-prerequisites.sh` (core spec-kit helper) directly into the orchestrator body in their installed form. Do **not** rely on installer-side path rewriting. The in-repo `extensions/subagent-flow/commands/speckit.subagent-flow.run.md` is byte-for-byte what spec-kit copies to `.specify/extensions/subagent-flow/commands/speckit.subagent-flow.run.md` — no transformation, no frontmatter `scripts:` redirection.

**Rationale**:
- The bundled `git` extension already writes installed paths directly in its command bodies (e.g., `extensions/git/commands/speckit.git.commit.md` references `.specify/extensions/git/scripts/bash/auto-commit.sh` verbatim). This is the established convention and what the spec's Assumption now codifies after the C2 realignment.
- The path-rewriting mechanism described in `EXTENSION-DEVELOPMENT-GUIDE.md` for the `scripts:` frontmatter field rewrites to `.specify/scripts/bash/...` (the core-scripts path), not `.specify/extensions/<id>/scripts/bash/...` (the extension-scripts path). It is the wrong rewriting target for extension-owned helpers and would silently produce broken in-body references. The frontmatter mechanism is unused by `git`'s `.md` files for the same reason.
- The core spec-kit helper `check-prerequisites.sh` is shipped by `specify init` at `.specify/scripts/bash/check-prerequisites.sh`, present in any spec-kit project. The orchestrator references it with that full installed path so a reader of the in-repo file sees the same string the AI agent will execute.
- Spec C2 realignment confirms this: the Assumptions block now says "Script paths are authored in installed form (per research.md Decision 7) … The spec-kit extension installer does not rewrite paths at install time; the in-repo command file is byte-for-byte what lands at `.claude/commands/speckit.subagent-flow.run.md`."

**Alternatives considered**:
- Use the documented `scripts:` frontmatter field with `../../scripts/bash/count-open-tasks.sh` and rely on the installer to rewrite it: rejected. The rewriting target is `.specify/scripts/bash/...` (core scripts path), not `.specify/extensions/<id>/scripts/bash/...` (extension scripts path). It would rewrite to the wrong location.
- Hard-code an absolute path: rejected; project-relative paths are portable across user machines.
- Leave the original `bash scripts/bash/count-open-tasks.sh` relative form (as in the fork's repo-root `.claude/commands/speckit-flow.md`) and depend on cwd: rejected. After install, the orchestrator runs from the project root, but the script no longer lives at `scripts/bash/...` — it lives under `.specify/extensions/subagent-flow/scripts/bash/`. The relative form would silently fail.

---

## Decision 8: Removed fork-root duplicates of the orchestration delta

**Decision**: As part of this packaging change, delete from the fork's repo root:

- `.claude/commands/speckit-flow.md` (replaced by `extensions/subagent-flow/commands/speckit.subagent-flow.run.md`)
- `.claude/agents/speckit-*.md` (replaced by `extensions/subagent-flow/agents/speckit-*.md`)
- `scripts/bash/count-open-tasks.sh` and `scripts/bash/build-claude-agents.sh` (moved into `extensions/subagent-flow/scripts/bash/`)

Keep `templates/commands/*.md` in place — those are upstream-derived source files, consumed by the generator at bake time. They are not duplicates; they are inputs.

**Rationale**:
- Two sources of truth for the same orchestrator body invite drift. The maintainer's CI bake against `templates/commands/*.md` already produces the canonical agent set; keeping a separate `.claude/agents/` copy at the fork root is redundant once the extension exists.
- The fork's `.claude/commands/speckit-flow.md` was only ever useful for in-repo dev-testing of the orchestrator. After packaging, the same dev-test pattern is `specify extension add --dev extensions/subagent-flow` from any spec-kit project (including the fork itself, dogfooded). The dev-only top-level files no longer earn their keep.
- The constitution principle "Verbatim Body, Rewritten Frontmatter" is reinforced: there is exactly one place the agent bodies live (`templates/commands/*.md` upstream → generator → baked into the extension), and no shadow copies at the fork root.

**Alternatives considered**:
- Keep the fork-root files as a dev convenience: rejected per the two-sources-of-truth concern.
- Symlink the fork-root files into the extension: rejected. Symlinks in shipped extension packages break under ZIP-based install (Zip Slip protections, link-following ambiguity across OSes).

---

## Decision 9: Bootstrap step implemented as inline bash in the orchestrator body (NOT a separate script)

**Decision**: The transparent bootstrap step that handles fresh-install / upgrade-drift refresh of `.claude/agents/speckit-<phase>.md` is implemented as an inline bash block inside `commands/speckit.subagent-flow.run.md`, at the very top of the orchestrator body, before Phase 1 specify. It is NOT a separate Bash script invoked from the body. The block is approximately ten lines: a `for` loop over the seven phase names, a `cmp -s` between source and deployed, and a `cp` on miss. If the source dir under `.specify/extensions/subagent-flow/agents/` is itself absent, the block exits 1 with a multiline error message containing (a) the literal list of missing source paths, (b) the recovery command `specify extension add subagent-flow`, and (c) the README path `.specify/extensions/subagent-flow/README.md`.

Sketch of the inline block (final form lives in the orchestrator body at implementation time; exact wording may differ but the shape is fixed):

```bash
SRC=.specify/extensions/subagent-flow/agents
DST=.claude/agents
if [ ! -d "$SRC" ]; then
  echo "ERROR: subagent-flow source dir missing: $SRC" >&2
  echo "  recovery: specify extension add subagent-flow" >&2
  echo "  see also: .specify/extensions/subagent-flow/README.md" >&2
  exit 1
fi
mkdir -p "$DST"
for p in specify plan tasks analyze implement checklist taskstoissues; do
  s="$SRC/speckit-$p.md"; d="$DST/speckit-$p.md"
  [ -f "$s" ] || { echo "ERROR: missing source: $s" >&2; exit 1; }
  cmp -s "$s" "$d" || cp "$s" "$d"
done
```

**Rationale**:
- The orchestrator command body is already where the per-feature workflow control lives. Threading the bootstrap through a separate Bash script adds an extra path indirection (the orchestrator would have to `bash .specify/extensions/subagent-flow/scripts/bash/bootstrap-agents.sh`) and a second file to maintain. The body already invokes Bash for `count-open-tasks.sh` between sittings, so the inline form does not introduce a new tool-surface dependency.
- The shipped `build-claude-agents.sh` regen script is NOT a drop-in for the bootstrap. The regen script's purpose is to *generate* agent files from a phase source layout (flat `templates/commands/` or skill `.claude/skills/speckit-<phase>/SKILL.md`) by rewriting frontmatter and injecting the `AUTO-GENERATED` header. It is a build tool. The bootstrap, by contrast, is a *deployment* step: copy already-baked files from one disk location to another, gated by `cmp -s`. Conflating the two roles would put deployment logic into a build tool that ordinary users never run.
- The inline form makes the bootstrap visible to anyone reading the orchestrator body. No hidden indirection. The constitution's Principle II (verbatim body, rewritten frontmatter) is reinforced: the body is a complete, self-contained workflow description.
- The seven-phase list is fixed by the constitution's `SKIP_PHASES = (clarify constitution)` rule. Hard-coding it inline (vs reading from a config file or env var) is appropriate because the list is part of the orchestrator's contract, not user-tunable input.
- `cmp -s` is a byte-comparison primitive available in every POSIX system; no parsing of frontmatter or content-aware diffing is needed. The decision rule is simple: "if the files don't match byte-for-byte, copy". This satisfies the "disk is truth" principle (V) cleanly.

**Alternatives considered**:
- Separate script `scripts/bash/bootstrap-agents.sh` invoked from the orchestrator body: rejected per the indirection concern above. Also creates a second source of truth for the seven-phase list (the script would need to encode it; the orchestrator already encodes it in its Phase 1..6 references). Two encodings invite drift.
- Re-purpose `build-claude-agents.sh` as the bootstrap by adding a "deploy-only" mode (skip the generator pass, just copy from `agents/` to `.claude/agents/`): rejected. Overloading a build tool with deployment responsibilities muddies its contract; readers of the orchestrator body would see `bash build-claude-agents.sh` and reasonably expect a generator pass (which they don't want at runtime).
- Use `rsync` instead of a `cmp -s`+`cp` loop: rejected. `rsync` is not guaranteed to be installed on every Bash-equipped host; `cmp` and `cp` are POSIX-baseline.
- Use a Python one-liner via the AI agent's Bash tool: rejected. The orchestrator already targets a Bash-only execution surface (constraint #2 — no new runtime deps). Mixing languages adds maintenance cost.

---

## Open questions resolved

| Question | Resolution |
|---|---|
| I2 — Manifest schema for the baked agent payload (`provides.agents` schema extension vs hooks) | Decision 6 (Path 3): neither. The manifest uses no field beyond schema 1.0; provisioning is handled by the orchestrator's own command-body inline bootstrap (Decision 9). Option (a), option (b-old), and option (b-intermediate) all require either spec-kit core changes or a user-visible install-time step; Path 3 requires neither. Locked in at release time. |
| Uninstall semantics for pre-baked agent files | Decision 6 (Path 3): the seven `.claude/agents/speckit-*.md` files persist across `specify extension remove` (they belong to the user's project after bootstrap, not to the extension's tracked payload). README documents the one-line manual cleanup. The `--keep-config` flag is a no-op for this extension. |
| Should the generator be a slash command? | No (Decision 1, Decision 2). Internal/power-user tool, invoked as bash. |
| Where do agent files live inside the extension payload? | `extensions/subagent-flow/agents/` (Decision 3). Installer copies them to `.specify/extensions/subagent-flow/agents/`; the orchestrator's inline bootstrap copies them from there into `.claude/agents/` on first invocation (transparently, no user action). |
| How does the orchestrator find the helper script post-install? | Direct write of `.specify/extensions/subagent-flow/scripts/bash/count-open-tasks.sh` in the command body (Decision 7). |
| What goes in `requires.tools`? | Nothing (FR-014). Host-agent capability documented narratively in README (Decision 4). |
| How does the maintainer keep baked agents in sync with upstream? | Scheduled GitHub Actions workflow with `workflow_dispatch`, locally verifiable via `nektos/act` (Decision 5). |
| Do the fork-root copies stay? | No (Decision 8). One source of truth: the extension package. |
| Where does the bootstrap step live (script vs inline)? | Inline bash in the orchestrator body, ~10 lines (Decision 9). NOT a separate script; NOT reusing `build-claude-agents.sh`. |

No NEEDS CLARIFICATION items remain. The I2 decision is pre-committed via Path 3; no install-time fork remains in the task graph.
