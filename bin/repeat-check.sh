#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/project.sh"
cd "$here" 2>/dev/null || exit 0
CLAUDE_PROJECT_DIR="$root" exec python3 -m refactor.reporting.repeat_check "$@"
