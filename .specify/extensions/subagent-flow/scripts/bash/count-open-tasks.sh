#!/usr/bin/env bash
# Print the integer count of unchecked task lines (^- \[ \]) in $1.
#
# Used by .claude/commands/speckit-flow.md's Phase 6 loop to decide whether
# another speckit-implement sitting is needed. The loop reads tasks.md from
# disk every iteration; this helper is the single point that turns disk state
# into a number.
#
# Edge cases:
#   - $1 missing/empty           -> usage on stderr, exit 1
#   - file at $1 does not exist  -> print 0, exit 0
#                                   (FR-009: missing tasks.md reads as
#                                   "no open tasks", so the orchestrator
#                                   skips the implement loop)
#   - file exists, zero matches  -> print 0, exit 0

set -euo pipefail

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  echo "usage: count-open-tasks.sh <path-to-tasks.md>" >&2
  exit 1
fi

path="$1"

if [[ ! -f "$path" ]]; then
  echo 0
  exit 0
fi

count=$(grep -c '^- \[ \]' "$path" || true)
echo "${count:-0}"
