#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/project.sh"
dir="$root/$sources"

[ -d "$dir" ] || exit 0

files=$(find "$dir" -type f \( -name '*.cpp' -o -name '*.h' \) | wc -l | tr -d ' ')
lines=$(find "$dir" -type f \( -name '*.cpp' -o -name '*.h' \) -exec cat {} + | wc -l | tr -d ' ')

printf '{"systemMessage":"%s/: %s lines across %s files","suppressOutput":true}\n' "$sources" "$lines" "$files"
