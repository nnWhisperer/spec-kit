<!--
SYNC IMPACT REPORT
==================
Version change: 1.1.1 → 1.1.2
Bump rationale: PATCH — documentation defect fix surfaced by /speckit-analyze
  (finding C1) during the subagent-flow extension's feature flow. Principle I
  previously enumerated `constitution` among non-interactive subagent phases,
  contradicting Principle III which places `constitution` in SKIP_PHASES as an
  interactive in-session phase. All shipped artifacts (the generator's
  SKIP_PHASES, the /speckit.subagent-flow.run orchestrator's "Never invoke
  speckit-constitution" operating rule, the seven baked agent files which
  exclude constitution) already implement Principle III's reading; Principle
  I's enumeration was the defect. No principle semantics change; only the
  enumeration text in Principle I is shortened to align with implementation.
Modified principles:
  - I. Subagent Phase Isolation — enumeration shortened from 8 phases to 7 by
    removing `constitution`. Title, MUST rule, and rationale unchanged.
Added sections: (none)
Removed sections: (none)
Templates reviewed for alignment:
  - ✅ .specify/memory/constitution.md (this file)
  - ✅ extensions/subagent-flow/scripts/bash/build-claude-agents.sh
       (SKIP_PHASES comment now cites Principle I as authority — both
       principles now agree, and Principle I is NON-NEGOTIABLE)
  - ✅ .specify/extensions/subagent-flow/scripts/bash/build-claude-agents.sh
       (deployed mirror of the source above; kept in sync)
  - n/a .specify/templates/plan-template.md (driven dynamically from this file)
  - n/a .specify/templates/spec-template.md / tasks-template.md
  - n/a .specify/templates/commands/*.md (Principle II forbids fork edits)
Follow-up TODOs:
  - TODO(PROJECT_NAME): "Spec Kit Subagent Fork" is a working name.
-->

# Spec Kit Subagent Fork Constitution

## Core Principles

### I. Subagent Phase Isolation (NON-NEGOTIABLE)

Each non-interactive speckit phase — `specify`, `plan`, `tasks`, `analyze`, `implement`, `checklist`, `taskstoissues` — MUST execute in an isolated subagent context spawned via the Agent tool with `subagent_type=speckit-<phase>`. Phases MUST NOT share conversational state; cross-phase handoff occurs exclusively through artifacts on disk under `specs/<NNN-feature>/`. Interactive phases (`clarify`, `constitution`) are NOT in scope here — they are governed by Principle III.

Rationale: prevents context pollution and makes the workflow reproducible and resumable. Each phase's output depends only on disk state, not on the orchestrator's chat history.

### II. Verbatim Body, Rewritten Frontmatter

Subagent files under `.claude/agents/speckit-*.md` MUST be generated mechanically from `templates/commands/<phase>.md` by `scripts/bash/build-claude-agents.sh`. Bodies are copied verbatim; only the frontmatter is rewritten to match the subagent schema. Hand-editing generated agent files is forbidden — regenerate instead.

Rationale: protects against drift from upstream and keeps the fork merge-compatible with `github/spec-kit`. The generator is the only authorised adapter layer.

### III. Interactive Phases Run In-Session (Orchestrator-Invoked Where In Scope)

Phases requiring interactive question-and-answer with the human — currently `clarify` and `constitution` — MUST NOT be subagent-ified, and MUST be retained in the generator's `SKIP_PHASES`. They MUST remain installed as slash commands / skills (`.claude/skills/speckit-<phase>/SKILL.md`).

Phases that fall **within the per-feature flow** (currently only `clarify`) MUST be invoked by the orchestrator (`/speckit-flow`) via the `Skill` tool at the appropriate point — the orchestrator MUST NOT pause and ask the user to manually type the slash command.

Phases that fall **outside the per-feature flow** (currently only `constitution`) MUST NEVER be invoked by the orchestrator. They are user-triggered only (via `/speckit-constitution`). The orchestrator's scope is **per-feature** work; project-bootstrap work is explicitly out of scope.

When an in-scope interactive phase is invoked from the orchestrator, its body expands inline in the main session, inheriting the orchestrator's full conversational context.

Rationale: interactive phases need rich context — the spec content, prior discussion, accumulated state — to ask well-targeted questions and reply to follow-ups in detail. Isolating them in a subagent would strip that context. The trade-off is intentional: only non-interactive per-feature phases pay the cost of context isolation. Excluding `constitution` from the orchestrator's flow keeps the orchestrator's scope tight (per-feature only) and prevents accidental constitution changes during what the user expects to be a feature build.

### IV. Orchestrator Delegates, Never Edits

The orchestrator slash command (`/speckit-flow`) MUST only (a) delegate to phase subagents, (b) verify artifacts on disk between phases, and (c) prompt the user when a hand-off requires human input. It MUST NOT directly edit `spec.md`, `plan.md`, `tasks.md`, or any phase output. On phase failure, it surfaces the failure verbatim and stops — no auto-retry.

Rationale: keeps a clear chain of responsibility. The orchestrator's job is routing and verification, not authorship.

### V. Disk Is Truth

Cross-phase state MUST live on disk, not in conversational memory. After each phase subagent returns, the orchestrator (and any consumer downstream of it) MUST re-read artifacts to verify state, rather than relying on the agent's returned message. Subagent return messages may be used as status hints, never as the source of truth for what was produced.

Rationale: subagent return messages are opaque summaries that can omit, misreport, or paraphrase. The artifacts themselves are the contract.

## Upstream Compatibility

The fork MUST remain merge-compatible with the upstream `github/spec-kit` repository's `templates/commands/*.md` source files. The generator is the only adapter layer between upstream commands and Claude Code subagents. Forking individual command bodies into `.claude/agents/` is prohibited — desired behavior changes go either into the upstream templates (proposed back upstream when generally useful) or into the generator's per-phase configuration (`PHASE_TOOLS`, `SKIP_PHASES`, default tools).

When new phases are added upstream, they become subagents automatically on the next generator run unless explicitly excluded. Removed upstream phases require deleting the stale `.claude/agents/speckit-<phase>.md` file as part of the merge.

## Development Workflow

- Changes to a phase's instructions: edit `templates/commands/<phase>.md`; re-run `scripts/bash/build-claude-agents.sh`.
- Changes to orchestration logic, phase ordering, or user-interaction points: edit `.claude/commands/speckit-flow.md`.
- Changes to subagent frontmatter (tool surface, skip list, default tools): edit `scripts/bash/build-claude-agents.sh`; re-run it.
- A change touching all three of the above simultaneously is a structural change and requires this constitution to be re-validated (and possibly amended).
- After merging upstream, always re-run the generator before testing the workflow.

## Governance

This constitution governs the fork's additions to upstream spec-kit. Upstream Spec-Driven Development principles (specifications as the source of truth, code as regenerated output) remain authoritative for anything this document does not contradict.

Amendments follow Semantic Versioning:
- **MAJOR**: removal or backward-incompatible redefinition of a principle, or a governance change.
- **MINOR**: addition of a new principle or materially expanded guidance.
- **PATCH**: clarifications, wording fixes, non-semantic refinements.

All PRs touching `.claude/agents/`, `.claude/commands/speckit-flow.md`, `scripts/bash/build-claude-agents.sh`, or `templates/commands/` MUST verify constitution compliance before merge. Reviewers SHOULD reject changes that:
- hand-edit generated subagent files (violates Principle II);
- introduce direct editing of phase artifacts from the orchestrator (violates Principle IV);
- rely on subagent return messages as authoritative state (violates Principle V).

Merging upstream changes MUST be followed by re-running the generator and reviewing whether new phases require entries in `PHASE_TOOLS` or `SKIP_PHASES`.

**Version**: 1.1.2 | **Ratified**: 2026-05-13 | **Last Amended**: 2026-05-14
