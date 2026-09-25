#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/project.sh"

rules="$(cat "$suite_root/rules/systematic.md")"$'\n\n'"$(cat "$suite_root/rules/style.md")"

if [ -n "$rules_file" ] && [ -f "$rules_file" ]; then
    project=$(HEADING="$project_rules" awk '
        BEGIN {
            heading = ENVIRON["HEADING"]
            level = heading
            sub(/[^#].*$/, "", level)
            level = length(level)
        }
        inside == 1 && /^#+[[:space:]]/ {
            mark = $0
            sub(/[^#].*$/, "", mark)
            if (length(mark) <= level) { exit }
        }
        inside == 0 && index($0, heading) == 1 { inside = 1 }
        inside == 1 { print }
    ' "$rules_file")
    if [ -n "$project" ]; then
        rules="${rules}"$'\n\n'"${project}"
    fi
fi

case "${1:-}" in
    --hook)
        jq -n --arg ctx "$rules" \
          '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'
        ;;
    *)
        printf '%s\n' "$rules"
        ;;
esac
