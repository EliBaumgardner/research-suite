root="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$root" 2>/dev/null || exit 0

sources="Source"
build_target=""
scanner=""
rules_file=""
project_rules="### Project Design Rules"
analyst_profile=".gemini/GEMINI.md"
issues_file=".claude/notes/ongoing-issues.md"
core_purpose_api=""
kept_small_classes=""
disabled_rules=""
project_unchecked=""
project_checks=""

eval "$(python3 - <<'PY' 2>/dev/null
import os
import shlex
import refactor
from refactor.workspace import CONFIG

suite = CONFIG.get("suite", {})
values = {
    "sources": CONFIG["sources"],
    "build_target": CONFIG["build_target"],
    "scanner": os.path.join(os.path.dirname(refactor.__file__), "cxx-scan.awk"),
    "project_rules": suite.get("project_rules", "### Project Design Rules"),
    "analyst_profile": suite.get("analyst_profile", ".gemini/GEMINI.md"),
    "issues_file": suite.get("issues_file", ".claude/notes/ongoing-issues.md"),
    "core_purpose_api": "\n".join(suite.get("core_purpose_api", [])),
    "kept_small_classes": "\n".join(suite.get("kept_small_classes", [])),
    "disabled_rules": "\n".join(suite.get("disabled_rules", [])),
    "project_unchecked": "\n".join(suite.get("unchecked", [])),
    "project_checks": "\n".join(
        "\x1f".join([check["rule"], check.get("label", check["rule"]), check.get("paths", ""),
                   str(int(check.get("in_functions", False))), check.get("skip_functions", ""),
                   check["pattern"]])
        for check in suite.get("checks", [])),
}
if "rules_file" in suite:
    values["rules_file"] = suite["rules_file"]
for name, value in values.items():
    print("%s=%s" % (name, shlex.quote(value)))
PY
)"

if [ -z "$rules_file" ]; then
    for candidate in .claude/CLAUDE.md CLAUDE.md; do
        if [ -f "$candidate" ]; then
            rules_file="$candidate"
            break
        fi
    done
fi

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
