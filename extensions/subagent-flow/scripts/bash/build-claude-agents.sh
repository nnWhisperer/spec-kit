#!/usr/bin/env bash
# Generate Claude Code subagent files from spec-kit command sources.
#
# Reads:  $SRC_DIR — layout auto-detected as either:
#           flat:  $SRC_DIR/<phase>.md                 (e.g. templates/commands,
#                                                       used in spec-kit dev)
#           skill: $SRC_DIR/speckit-<phase>/SKILL.md   (e.g. .claude/skills,
#                                                       used in any speckit-
#                                                       installed project)
#         If SRC_DIR is unset, tries templates/commands first, then
#         .claude/skills. Extension skills (anything with a hyphen left
#         in the phase name after stripping "speckit-", e.g. speckit-git-*)
#         are silently skipped — only workflow phases are processed.
# Writes: $OUT_DIR/speckit-<phase>.md  (default: .claude/agents)
#
# Each generated agent is invokable via the Agent tool with
# subagent_type=speckit-<phase>, giving an isolated context per phase.
# Bodies are copied verbatim from the source; only the frontmatter is
# rewritten to match the subagent schema.
#
# Run from the project root:
#     bash scripts/bash/build-claude-agents.sh
# Re-run whenever the source changes (e.g. after a speckit update).

set -euo pipefail

# Auto-detect SRC_DIR when not provided.
if [[ -z "${SRC_DIR:-}" ]]; then
  if [[ -d "templates/commands" ]]; then
    SRC_DIR="templates/commands"
  elif [[ -d ".claude/skills" ]]; then
    SRC_DIR=".claude/skills"
  else
    SRC_DIR="templates/commands"  # keep for the error message below
  fi
fi
OUT_DIR="${OUT_DIR:-.claude/agents}"

# Phases listed here are not generated as subagents because they are
# orchestrated in-session as skills/slash commands instead. The orchestrator
# invokes them via the Skill tool so their bodies expand inline in the main
# session, sharing the orchestrator's full conversational context.
#
# Authority: Constitution Principle I (Subagent Phase Isolation,
# NON-NEGOTIABLE) enumerates the seven non-interactive phases that MUST
# run as subagents — `clarify` and `constitution` are NOT in that list
# because they are interactive. Principle III gives the operational rule
# (in-session expansion via the Skill tool). Both principles agree.
#
# - clarify: must dialogue with the user using full session context
#   (feature description, specify output, prior discussion).
# - constitution: project-bootstrap, not per-feature workflow. It is
#   interactive (collects principles/values) and benefits from main-session
#   context. The /speckit-flow orchestrator never invokes it.
SKIP_PHASES=(clarify constitution)

# Tool surface per phase. Phases not listed get DEFAULT_TOOLS.
# Notably, Agent is omitted from every phase to prevent recursive spawning.
DEFAULT_TOOLS="Read, Write, Edit, Bash, Glob, Grep"
declare -A PHASE_TOOLS=(
  [plan]="Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch, Skill"
  [implement]="Read, Write, Edit, Bash, Glob, Grep, TodoWrite, Skill"
  [tasks]="Read, Write, Edit, Bash, Glob, Grep, Skill"
  [analyze]="Read, Bash, Glob, Grep, Skill"
  [taskstoissues]="Read, Bash, Glob, Grep"
)

if [[ ! -d "$SRC_DIR" ]]; then
  echo "error: source directory not found: $SRC_DIR" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

is_skipped() {
  local phase="$1" s
  for s in "${SKIP_PHASES[@]}"; do
    [[ "$s" == "$phase" ]] && return 0
  done
  return 1
}

# First "description:" line inside the source frontmatter block. Tolerates
# values with or without surrounding double/single quotes (flat layout is
# unquoted; skill SKILL.md files use double quotes).
extract_description() {
  awk '
    /^---$/ { c++; if (c==2) exit; next }
    c==1 && /^description:[[:space:]]/ {
      sub(/^description:[[:space:]]*/, "")
      if (sub(/^"/, "")) sub(/"$/, "")
      else if (sub(/^'\''/, "")) sub(/'\''$/, "")
      print
      exit
    }
  ' "$1"
}

# Everything after the closing --- of the source frontmatter.
extract_body() {
  awk '
    /^---$/ { c++; next }
    c>=2 { print }
  ' "$1"
}

# Escape a string for a YAML double-quoted scalar.
yaml_double_quote() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

count=0
skipped=0
# Detect layout: flat (<phase>.md at SRC_DIR root) vs skill
# (speckit-<phase>/SKILL.md subdirectories).
shopt -s nullglob
flat_sources=("$SRC_DIR"/*.md)
skill_sources=("$SRC_DIR"/speckit-*/SKILL.md)
shopt -u nullglob

if [[ ${#flat_sources[@]} -gt 0 ]]; then
  layout="flat"
  sources=("${flat_sources[@]}")
elif [[ ${#skill_sources[@]} -gt 0 ]]; then
  layout="skill"
  sources=("${skill_sources[@]}")
else
  echo "error: no command sources in $SRC_DIR" >&2
  echo "       expected <phase>.md (flat) or speckit-<phase>/SKILL.md (skill)" >&2
  exit 1
fi

for src in "${sources[@]}"; do
  if [[ "$layout" == "flat" ]]; then
    phase="$(basename "$src" .md)"
  else
    phase="$(basename "$(dirname "$src")")"
    phase="${phase#speckit-}"
    # Workflow phase names are single tokens; anything with a remaining
    # hyphen is an extension command skill (e.g. speckit-git-commit), not
    # a workflow phase. Skip silently.
    case "$phase" in
      *-*) continue ;;
    esac
  fi

  if is_skipped "$phase"; then
    echo "skip   speckit-$phase (in SKIP_PHASES)"
    skipped=$((skipped+1))
    continue
  fi

  desc="$(extract_description "$src")"
  if [[ -z "$desc" ]]; then
    echo "warn   $src has no description: line; using fallback" >&2
    desc="Spec-kit workflow phase: $phase"
  fi

  body="$(extract_body "$src")"
  tools="${PHASE_TOOLS[$phase]:-$DEFAULT_TOOLS}"
  out="$OUT_DIR/speckit-$phase.md"

  {
    echo "---"
    echo "name: speckit-$phase"
    echo "description: $(yaml_double_quote "$desc")"
    echo "tools: $tools"
    echo "---"
    echo
    echo "<!-- AUTO-GENERATED from $src by scripts/bash/build-claude-agents.sh. Do not edit by hand. -->"
    echo
    echo "When invoked as a subagent, the orchestrator's invocation prompt is the value of \`\$ARGUMENTS\` referenced below. Treat it as the user input."
    echo
    printf '%s\n' "$body"
  } > "$out"

  echo "wrote  $out"
  count=$((count+1))
done

echo "done: $count agent file(s) written, $skipped skipped"
