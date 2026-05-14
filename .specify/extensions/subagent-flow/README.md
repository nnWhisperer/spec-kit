# Subagent Flow Orchestrator

## What this extension does

`subagent-flow` packages a per-feature spec-kit orchestrator that runs the full workflow — **specify → clarify → plan → tasks → (analyze, optional) → implement** — by delegating each non-interactive phase to an isolated subagent via Claude Code's `Agent` tool, while keeping the interactive `clarify` phase in the main session via the `Skill` tool. The implement phase runs as a chunked loop across sittings, terminating only when `tasks.md` has no remaining unchecked tasks. Each subagent gets its own context budget; the main session stays small and stays in charge of the workflow's branch points.

## Install

```bash
specify extension add subagent-flow
```

Local dev install (from a checkout of the source repo):

```bash
specify extension add --dev path/to/extensions/subagent-flow
```

## First-run experience

On the first invocation of `/speckit.subagent-flow.run`, the orchestrator runs a small inline bash block (Phase 0) at the very top of its body that silently copies the seven baked subagent files from `.specify/extensions/subagent-flow/agents/` into `.claude/agents/`. You see no extra prompt — the orchestrator proceeds straight to Phase 1. Subsequent invocations are no-ops unless an extension upgrade has changed source content, in which case the bootstrap transparently refreshes `.claude/agents/`. This is Path 3: the orchestrator owns the agent-file deployment lifecycle; the spec-kit installer does not write to `.claude/agents/`.

## Use

```text
/speckit.subagent-flow.run "<feature description>"
```

The orchestrator walks the per-feature workflow:

1. **Phase 1 — specify**: invokes `Agent(subagent_type=speckit-specify)` with your feature description as the prompt; verifies `spec.md` exists on disk afterwards.
2. **Phase 2 — clarify (in-session, via Skill)**: expands `speckit-clarify` inline so it shares the main session's full context, asks targeted questions via `AskUserQuestion`, and encodes answers into the spec.
3. **Phase 3 — plan**: asks you for tech-stack/library choices in a single short question, then invokes `Agent(subagent_type=speckit-plan)`.
4. **Phase 4 — tasks**: invokes `Agent(subagent_type=speckit-tasks)` to break the plan into dependency-ordered tasks.
5. **Phase 5 — analyze (optional)**: asks whether to run an analyze pass; if yes, invokes `Agent(subagent_type=speckit-analyze)` and surfaces its findings.
6. **Phase 6 — implement (chunked loop)**: invokes `Agent(subagent_type=speckit-implement)` repeatedly. Between sittings, the orchestrator reads `tasks.md` from disk via `count-open-tasks.sh` and continues until no unchecked tasks remain (or a zero-progress safeguard halts it). Disk is the only inter-sitting contract; the implement subagent's returned message is treated as a status hint, never as truth.

The orchestrator delegates only — it never directly writes to `spec.md`, `plan.md`, or `tasks.md`.

## Uninstall

```bash
specify extension remove subagent-flow
```

This removes `.specify/extensions/subagent-flow/` entirely (manifest, scripts, README, the seven SOURCE-copy agent files). It deliberately **leaves the seven `.claude/agents/speckit-<phase>.md` files in place** because those are deployed copies the orchestrator owns at first invocation, not part of the extension's tracked payload after bootstrap. You retain the upstream-derived agent content, which is useful for direct `/speckit.<phase>` invocations outside this orchestrator.

If you want to scrub the deployed copies as well:

```bash
rm .claude/agents/speckit-{specify,plan,tasks,analyze,implement,checklist,taskstoissues}.md
```

The `--keep-config` flag is a no-op for this extension — there is no extension-owned config to preserve or remove independently of the extension dir.

## Power user: customising agent bodies

If you have customised the local SKILLs in `.claude/skills/speckit-<phase>/SKILL.md`, you can re-derive the seven SOURCE-copy agent files by running:

```bash
bash .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh
```

The generator auto-detects the source layout (`templates/commands/<phase>.md` flat layout preferred; falls back to `.claude/skills/speckit-<phase>/SKILL.md` skill layout). After regen, your next invocation of `/speckit.subagent-flow.run` will detect the content drift via the bootstrap's `cmp -s` check and propagate the changes to `.claude/agents/` automatically.

Ordinary users do not need to run the generator — the extension ships with pre-baked agents from upstream `templates/commands/*.md`, refreshed by maintainer CI before each release.

## Compatibility

- spec-kit `>=0.2.0`.
- Claude Code is the reference host. The orchestrator requires the host AI agent to expose two tools: `Agent` (for subagent delegation) and `Skill` (for inline clarify expansion). Hosts that lack these tools cannot run the orchestrator end-to-end. Install does not gate on host capability — the failure surfaces at the first `/speckit.subagent-flow.run` invocation.

## Recovery

The orchestrator's Phase 0 bootstrap has exactly one user-visible failure path: if the source directory `.specify/extensions/subagent-flow/agents/` is missing or partially populated (a sign of an interrupted install or a hand-deletion of the extension directory), the bootstrap exits with a multiline error pointing at `specify extension add subagent-flow` for recovery and `.specify/extensions/subagent-flow/README.md` (this file) for documentation. Re-install with `specify extension add subagent-flow` and re-invoke the orchestrator.

Under all other conditions (deployed copy missing, deployed copy tampered, content drift after an extension upgrade) the bootstrap self-heals silently — no user action required.

---

## Maintainer section

### Re-baking the agent files from upstream

The seven baked agent files at `extensions/subagent-flow/agents/` are generated from upstream `templates/commands/*.md` by `build-claude-agents.sh`. A scheduled GitHub Actions workflow (`.github/workflows/subagent-flow-resync.yml`) re-runs the generator weekly and opens a PR if upstream drift produces a non-empty diff.

Local verification of the workflow with `nektos/act`:

```bash
act workflow_dispatch -W .github/workflows/subagent-flow-resync.yml --container-architecture linux/amd64
```

The workflow is pinned to `actions/checkout@v4` and `peter-evans/create-pull-request@v6` — both versions `act` is known to support. The workflow uses no `pull_request_target`, no GitHub-only services, and no GitHub-only runners.

### Generator contract

`build-claude-agents.sh` is idempotent: re-running it against the same source produces byte-identical output. It silently skips `clarify` and `constitution` phases (per Constitution Principle III), and skips extension command skills (phase names with a hyphen after `speckit-`, e.g., `speckit-git-commit`). The per-phase tool surface is encoded in the script's `PHASE_TOOLS` associative array.
