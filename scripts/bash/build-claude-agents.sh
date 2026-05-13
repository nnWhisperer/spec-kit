#!/usr/bin/env bash
# Generate Claude Code subagent files from spec-kit command templates.
#
# Reads:  $SRC_DIR/<phase>.md          (default: templates/commands)
# Writes: $OUT_DIR/speckit-<phase>.md  (default: .claude/agents)
#
# Each generated agent is invokable via the Agent tool with
# subagent_type=speckit-<phase>, giving an isolated context per phase.
# Bodies are copied verbatim from the source command templates; only the
# frontmatter is rewritten to match the subagent schema.
#
# Run from the project root:
#     bash scripts/bash/build-claude-agents.sh
# Re-run whenever templates/commands/*.md changes.

set -euo pipefail

SRC_DIR="${SRC_DIR:-templates/commands}"
OUT_DIR="${OUT_DIR:-.claude/agents}"

# Phases listed here are not generated as subagents because they are
# orchestrated in-session as skills/slash commands instead. The orchestrator
# invokes them via the Skill tool so their bodies expand inline in the main
# session, sharing the orchestrator's full conversational context.
# clarify is in this list because it must dialogue with the user using full
# session context (feature description, specify output, prior discussion).
SKIP_PHASES=(clarify)

# Tool surface per phase. Phases not listed get DEFAULT_TOOLS.
# Notably, Agent is omitted from every phase to prevent recursive spawning.
DEFAULT_TOOLS="Read, Write, Edit, Bash, Glob, Grep"
declare -A PHASE_TOOLS=(
  [plan]="Read, Write, Edit, Bash, Glob, Grep, WebFetch, WebSearch"
  [implement]="Read, Write, Edit, Bash, Glob, Grep, TodoWrite"
  [analyze]="Read, Bash, Glob, Grep"
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

# First "description:" line inside the source frontmatter block.
extract_description() {
  awk '
    /^---$/ { c++; if (c==2) exit; next }
    c==1 && /^description:[[:space:]]/ {
      sub(/^description:[[:space:]]*/, "")
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
shopt -s nullglob
sources=("$SRC_DIR"/*.md)
shopt -u nullglob
if [[ ${#sources[@]} -eq 0 ]]; then
  echo "error: no .md files in $SRC_DIR" >&2
  exit 1
fi

for src in "${sources[@]}"; do
  phase="$(basename "$src" .md)"

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
