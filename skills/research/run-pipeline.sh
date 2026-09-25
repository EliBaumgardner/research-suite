#!/usr/bin/env bash
set -uo pipefail

subject="$*"
if [ -z "$subject" ]; then
    echo "usage: run-pipeline.sh <subject>" >&2
    exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../../lib/project.sh"

analysis=".claude/context/GeminiAnalysis"
unreviewed="$analysis/Unreviewed"
reviewed="$analysis/Reviewed"
proposals=".claude/context/Proposals"

mkdir -p "$unreviewed/ProgramAudits" "$unreviewed/ResearchReports" \
         "$reviewed/ProgramAudits" "$reviewed/ResearchReports" \
         "$proposals/Unimplemented" "$proposals/Implemented"

run_dir="$(mktemp -d "${TMPDIR:-/tmp}/research-suite.XXXXXX")"
summary="$run_dir/summary.txt"

log() {
    printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$summary"
}

fail() {
    log "FAILED at stage: $1"
    log "logs: $run_dir"
    exit 1
}

list_unreviewed() {
    find "$unreviewed/ProgramAudits" "$unreviewed/ResearchReports" -type f -name '*.md' | sort
}

outside_writes_since() {
    find .claude .gemini -type f -newer "$1" \
        ! -path "$unreviewed/*" ! -path "$reviewed/*" ! -path "$proposals/*" 2>/dev/null
}

log "subject: $subject"
log "commit: $(git rev-parse --short HEAD)"
log "logs: $run_dir"

case "$analyst" in
    agy)
        if [ -z "$analyst_model" ]; then
            analyst_model="gemini-3.1-pro-high"
        fi
        analyst_command=(agy --dangerously-skip-permissions --disable-slash-commands --print-timeout 0 --model "$analyst_model")
        ;;
    gemini)
        analyst_command=(gemini --approval-mode yolo)
        if [ -n "$analyst_model" ]; then
            analyst_command+=(-m "$analyst_model")
        fi
        ;;
    claude)
        analyst_command=(env -u CLAUDECODE claude --permission-mode auto)
        if [ -n "$analyst_model" ]; then
            analyst_command+=(--model "$analyst_model")
        fi
        ;;
    *)
        log "unknown analysis agent \"$analyst\" under [suite.pipeline] - use agy, gemini or claude"
        fail "configuration"
        ;;
esac

review_command=(env -u CLAUDECODE claude --permission-mode auto)
if [ -n "$review_model" ]; then
    review_command+=(--model "$review_model")
fi
propose_command=(env -u CLAUDECODE claude --permission-mode auto)
if [ -n "$propose_model" ]; then
    propose_command+=(--model "$propose_model")
fi

git status --porcelain > "$run_dir/git-before.txt"
list_unreviewed > "$run_dir/unreviewed-before.txt"
touch "$run_dir/analysis.marker"

if [ ! -f "$analyst_profile" ]; then
    log "no project profile at $analyst_profile - run /research-suite:init, or set analyst_profile under [suite] in .claude/refactor.toml"
    fail "analyze"
fi

analyze_command="$suite_root/gemini/analyze.toml"
analyze_prompt="$run_dir/analyze-prompt.md"

awk '/^prompt = """/ { inside = 1; next } inside && /^"""/ { inside = 0 } inside' "$analyze_command" \
    | while IFS= read -r line; do
        case "$line" in
            @\{*\})
                included="${line#@\{}"
                included="${included%\}}"
                if [ "$included" = "profile" ]; then
                    cat "$analyst_profile"
                else
                    cat "$suite_root/gemini/$included"
                fi
                ;;
            *)
                printf '%s\n' "${line//\{\{args\}\}/$subject}"
                ;;
        esac
    done > "$analyze_prompt"
if ! grep -q . "$analyze_prompt"; then
    log "could not read the analysis prompt from $analyze_command"
    fail "analyze"
fi

log "stage 1/3: analysis agent $analyst on ${analyst_model:-its default model}"
"${analyst_command[@]}" -p "$(cat "$analyze_prompt")" > "$run_dir/analyze.log" 2>&1 \
    || fail "analyze ($analyst exited $?, see analyze.log)"

list_unreviewed > "$run_dir/unreviewed-after.txt"
comm -13 "$run_dir/unreviewed-before.txt" "$run_dir/unreviewed-after.txt" > "$run_dir/new-reports.txt"
report_count="$(wc -l < "$run_dir/new-reports.txt" | tr -d ' ')"
if [ "$report_count" -ne 1 ]; then
    log "expected exactly one new report in $unreviewed, found $report_count"
    cat "$run_dir/new-reports.txt" >> "$summary"
    fail "analyze"
fi
report="$(cat "$run_dir/new-reports.txt")"
log "report: $report"

git status --porcelain > "$run_dir/git-after-analyze.txt"
outside_writes_since "$run_dir/analysis.marker" > "$run_dir/outside-writes.txt"
if ! cmp -s "$run_dir/git-before.txt" "$run_dir/git-after-analyze.txt" || [ -s "$run_dir/outside-writes.txt" ]; then
    log "the analysis agent wrote outside $unreviewed; nothing was reverted"
    diff "$run_dir/git-before.txt" "$run_dir/git-after-analyze.txt" >> "$summary"
    cat "$run_dir/outside-writes.txt" >> "$summary"
    fail "analyze guard"
fi

subfolder="$(basename "$(dirname "$report")")"
reviewed_report="$reviewed/$subfolder/$(basename "$report")"

log "stage 2/3: Claude review on ${review_model:-its default model}"
"${review_command[@]}" -p "/research-suite:review $report" > "$run_dir/review.log" 2>&1 \
    || fail "review (claude exited $?, see review.log)"

if [ ! -f "$reviewed_report" ]; then
    log "review did not write $reviewed_report"
    fail "review"
fi
if [ -f "$report" ]; then
    log "review left the original in place: $report"
fi
log "reviewed: $reviewed_report"
log "$(grep -m1 '^> Verdict:' "$reviewed_report")"

git status --porcelain > "$run_dir/git-after-review.txt"
if ! cmp -s "$run_dir/git-before.txt" "$run_dir/git-after-review.txt"; then
    log "review changed tracked or untracked files in the repo; nothing was reverted"
    diff "$run_dir/git-before.txt" "$run_dir/git-after-review.txt" >> "$summary"
    fail "review guard"
fi

touch "$run_dir/proposal.marker"

log "stage 3/3: Claude propose on ${propose_model:-its default model}"
"${propose_command[@]}" -p "/research-suite:propose $reviewed_report" > "$run_dir/propose.log" 2>&1 \
    || fail "propose (claude exited $?, see propose.log)"

git status --porcelain > "$run_dir/git-after-propose.txt"
if ! cmp -s "$run_dir/git-before.txt" "$run_dir/git-after-propose.txt"; then
    log "propose changed tracked or untracked files in the repo; nothing was reverted"
    diff "$run_dir/git-before.txt" "$run_dir/git-after-propose.txt" >> "$summary"
    fail "propose guard"
fi

find "$proposals/Unimplemented" -type f -name '*.md' -newer "$run_dir/proposal.marker" > "$run_dir/new-proposals.txt"
if [ -s "$run_dir/new-proposals.txt" ]; then
    while read -r written; do
        log "proposal: $written"
    done < "$run_dir/new-proposals.txt"
else
    log "no proposal written; propose.log says why"
fi

log "done"
