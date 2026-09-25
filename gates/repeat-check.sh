#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

cd "$here" 2>/dev/null || exit 0
CLAUDE_PROJECT_DIR="$root" exec python3 -m refactor.reporting.repeat_check "$@"
