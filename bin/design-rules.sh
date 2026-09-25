#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/../lib/project.sh"

mode="diff"
target=""

case "${1:-}" in
    --all)
        mode="all"
        ;;
    --file)
        mode="file"
        target="${2:-}"
        ;;
    --hook)
        mode="${2:-}"
        ;;
esac

payload=""
if [ "$mode" = "post-tool" ] || [ "$mode" = "stop" ]; then
    payload=$(cat)
fi

if [ "$mode" = "stop" ]; then
    active=$(printf '%s' "$payload" | jq -r '.stop_hook_active // false' 2>/dev/null)
    if [ "$active" = "true" ]; then
        exit 0
    fi
fi

if [ "$mode" = "post-tool" ]; then
    target=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    if [ -z "$target" ]; then
        exit 0
    fi
    target="${target#"$root"/}"
    case "$target" in
        "$sources"/*.cpp|"$sources"/*.h) ;;
        *) exit 0 ;;
    esac
fi

case "$mode" in
    all)
        files=$(find "$sources" -type f \( -name '*.cpp' -o -name '*.h' \) | sort)
        scope="all $sources files"
        ;;
    file|post-tool)
        if [ ! -f "$target" ]; then
            exit 0
        fi
        files="$target"
        scope="$target"
        ;;
    *)
        files=$( { git diff --name-only HEAD -- "$sources/*.cpp" "$sources/*.h" 2>/dev/null
                   git ls-files --others --exclude-standard -- "$sources/*.cpp" "$sources/*.h" 2>/dev/null; } \
                 | sort -u | while read -r candidate; do
                       if [ -f "$candidate" ]; then echo "$candidate"; fi
                   done )
        scope="files changed vs HEAD"
        ;;
esac

if [ -z "$files" ]; then
    if [ "$mode" = "post-tool" ] || [ "$mode" = "stop" ]; then
        exit 0
    fi
    echo "design-rules: no changed $sources files to check"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

addedmap="$work/added"
: > "$addedmap"

git diff -U0 -M HEAD -- "$sources/*.cpp" "$sources/*.h" 2>/dev/null | awk '
    /^\+\+\+ b\// { F = substr($0, 7); next }
    /^@@/ {
        if (F != "" && match($0, /\+[0-9]+(,[0-9]+)?/)) {
            spec = substr($0, RSTART + 1, RLENGTH - 1)
            n = split(spec, a, ",")
            start = a[1] + 0
            count = 1
            if (n > 1) { count = a[2] + 0 }
            for (i = 0; i < count; i++) { print F ":" (start + i) }
        }
    }
' >> "$addedmap"

for f in $files; do
    if ! git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        awk -v F="$f" '{ print F ":" FNR }' "$f" >> "$addedmap"
    fi
done

scope_added=1
if [ "$mode" = "all" ]; then
    scope_added=0
fi

only_added() {
    if [ "$scope_added" -eq 0 ]; then
        cat
        return
    fi
    awk -F: -v MAP="$addedmap" '
        BEGIN { while ((getline l < MAP) > 0) { keep[l] = 1 } }
        NF >= 2 { key = $1 ":" $2; if (key in keep) { print } }
    '
}

funcs="$work/funcs"
echo "$files" | tr ' ' '\n' | grep -v '^$' \
    | xargs awk -v MINBLOCK=999999 -f "$scanner" 2>/dev/null \
    | grep '^F' > "$funcs"

members="$work/members"
echo "$files" | tr ' ' '\n' | grep -E '\.h$' | xargs awk '
    FNR == 1 { access = ""; curclass = ""; depth = 0 }
    {
        line = $0
        sub(/\/\/.*$/, "", line)

        if (line ~ /^[[:space:]]*(class|struct)[[:space:]]+[A-Za-z_]/ && line !~ /;[[:space:]]*$/) {
            c = line
            sub(/^[[:space:]]*(class|struct)[[:space:]]+/, "", c)
            if (match(c, /^[A-Za-z_][A-Za-z0-9_]*/)) { curclass = substr(c, RSTART, RLENGTH) }
            access = "private"
            if (line ~ /^[[:space:]]*struct/) { access = "public" }
            next
        }
        if (line ~ /^[[:space:]]*public[[:space:]]*:/)    { access = "public";    next }
        if (line ~ /^[[:space:]]*protected[[:space:]]*:/) { access = "protected"; next }
        if (line ~ /^[[:space:]]*private[[:space:]]*:/)   { access = "private";   next }

        if (curclass == "" || access == "" || access == "public") { next }
        if (line !~ /;[[:space:]]*$/ || line ~ /\(/) { next }
        if (line ~ /^[[:space:]]*(using|typedef|friend|template|#|\})/) { next }

        n = line
        sub(/[[:space:]]*=.*$/, "", n)
        sub(/;[[:space:]]*$/, "", n)
        sub(/\[[^]]*\][[:space:]]*$/, "", n)
        if (n !~ /[[:space:]]/) { next }
        if (match(n, /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*$/)) {
            nm = substr(n, RSTART, RLENGTH)
            gsub(/[[:space:]]/, "", nm)
            print "M\t" curclass "\t" nm "\t" FILENAME "\t" FNR "\t" access
        }
    }
' 2>/dev/null > "$members"

classes="$work/classes"
echo "$files" | tr ' ' '\n' | grep -E '\.h$' | xargs awk '
    function squash(s,   g) {
        g = s
        while (sub(/<[^<>]*>/, "", g)) { }
        return g
    }
    function classify(d,   g, nm) {
        if (top < 1) { return }
        if (d ~ /^[[:space:]]*$/) { return }
        if (d ~ /(public|private|protected)[[:space:]]*:/) { return }
        if (d ~ /(^|[^A-Za-z0-9_])(using|typedef|friend|template|enum|union)[^A-Za-z0-9_]/) { return }
        if (d ~ /(^|[^A-Za-z0-9_])(class|struct)[[:space:]]+[A-Za-z_]/) { return }
        if (d ~ /(^|[^A-Za-z0-9_])override([^A-Za-z0-9_]|$)/) { over[top]++ }
        if (d ~ /(^|[^A-Za-z0-9_])virtual[^A-Za-z0-9_]/) { virt[top]++ }
        g = squash(d)
        if (g ~ /\(/) {
            fn[top]++
            nm = g
            sub(/\(.*$/, "", nm)
            if (match(nm, /[A-Za-z_~][A-Za-z0-9_]*[[:space:]]*$/)) {
                nm = substr(nm, RSTART, RLENGTH)
                gsub(/[[:space:]]/, "", nm)
                if (nm == cname[top] || nm ~ /^~/) { ctor[top]++ }
            }
            return
        }
        if (d ~ /;/) { var[top]++ }
    }
    FNR == 1 { depth = 0; top = 0; pending = 0; head = ""; decl = "" }
    {
        line = $0
        sub(/\/\/.*$/, "", line)
        gsub(/"[^"]*"/, "\"\"", line)

        if (pending == 0 && line ~ /(^|[^A-Za-z0-9_])(class|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/ && line !~ /;[[:space:]]*$/) {
            pending = 1
            head = line
            headline = FNR
        }
        else if (pending == 1) {
            head = head " " line
        }

        for (i = 1; i <= length(line); i++) {
            c = substr(line, i, 1)
            if (c == "{") {
                if (top > 0 && depth == bodyd[top] && pending == 0) { classify(decl); decl = "" }
                depth++
                if (pending == 1) {
                    top++
                    cname[top] = "?"
                    if (match(head, /(^|[^A-Za-z0-9_])(class|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/)) {
                        nm = substr(head, RSTART, RLENGTH)
                        sub(/^[^A-Za-z0-9_]*/, "", nm)
                        sub(/^(class|struct)[[:space:]]+/, "", nm)
                        cname[top] = nm
                    }
                    base[top] = 0
                    if (head ~ /:[[:space:]]*(public|protected|private|virtual)/) { base[top] = 1 }
                    bodyd[top] = depth
                    cline[top] = headline
                    cfile[top] = FILENAME
                    fn[top] = 0; var[top] = 0; over[top] = 0; ctor[top] = 0; virt[top] = 0
                    pending = 0
                    head = ""
                    decl = ""
                }
            }
            else if (c == "}") {
                if (top > 0 && depth == bodyd[top]) {
                    print cfile[top] "\t" cline[top] "\t" cname[top] "\t" base[top] "\t" fn[top] "\t" var[top] "\t" over[top] "\t" ctor[top] "\t" virt[top]
                    top--
                }
                depth--
                decl = ""
            }
            else if (top > 0 && depth == bodyd[top] && pending == 0) {
                decl = decl c
                if (c == ";") { classify(decl); decl = "" }
                else if (c == ":" && decl ~ /(public|protected|private)[[:space:]]*:$/) { decl = "" }
            }
        }
        if (top > 0 && depth == bodyd[top] && pending == 0) { decl = decl " " }
    }
' 2>/dev/null > "$classes"

violations=0
report=""

emit() {
    local rule="$1"
    local hits="$2"
    if printf '%s\n' "$disabled_rules" | grep -qxF -- "$rule"; then
        return
    fi
    if [ -n "$hits" ]; then
        violations=$((violations + 1))
        report="${report}"$'\n'"[VIOLATION] ${rule}"$'\n'"${hits}"$'\n'
    fi
}

inline_hits=$(echo "$files" | xargs grep -HnE '(^|[[:space:]])inline[[:space:]]' 2>/dev/null \
    | grep -F '(' | grep -v 'constexpr' | only_added)

ternary_hits=$(echo "$files" | xargs awk '
    { line = $0
      gsub(/::/, "@@", line)
      gsub(/"[^"]*"/, "@@", line)
      gsub(/\/\/.*$/, "", line)
      if (line ~ /\?[^:]*:/) printf "%s:%d:%s\n", FILENAME, FNR, $0 }
' 2>/dev/null | only_added)

comment_hits=$(echo "$files" | xargs awk '
    FNR == 1 { banner = 1 }
    banner {
        if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^[[:space:]]*(\/\/|\/\*|\*)/) { next }
        banner = 0
    }
    /#endif[[:space:]]*\/\// { next }
    /\/\/[[:space:]]*Created by/ { next }
    /\/\/=+/ { next }
    /(^|[^:"\/])\/\/|\/\*/ { printf "%s:%d:%s\n", FILENAME, FNR, $0 }
' 2>/dev/null | only_added)

brace_hits=$(echo "$files" | xargs awk '
    function balanced(s,   i, c, depth) {
        depth = 0
        for (i = 1; i <= length(s); i++) {
            c = substr(s, i, 1)
            if (c == "(") depth++
            if (c == ")") depth--
        }
        return depth == 0
    }
    prev != "" {
        if ($0 !~ /^[[:space:]]*\{/) printf "%s:%d:%s\n", FILENAME, prevline, prev
        prev = ""
    }
    /^[[:space:]]*(if|for|while)[[:space:]]*\(.*\)[[:space:]]*$/ {
        if (balanced($0)) { prev = $0; prevline = FNR; next }
    }
    /^[[:space:]]*else[[:space:]]*$/ { prev = $0; prevline = FNR; next }
    { prev = "" }
' 2>/dev/null | only_added)

tidy_out=""
tidy_skipped=""
if [ "$mode" != "post-tool" ]; then
    tidy_out=$(refactor.tidy --porcelain $files 2>"$work/tidy.err")
    if [ $? -gt 1 ]; then
        tidy_skipped=$(sed 's/^refactor: refused - //' "$work/tidy.err")
        tidy_out=""
    fi
fi

tidy_hits() {
    printf '%s\n' "$tidy_out" | awk -F'\t' -v RULE="$1" '
        $1 == RULE && NF >= 3 {
            split($2, at, ":")
            printf "%s:%s:%s\n", at[1], at[2], $3
        }
    ' | only_added
}

brace_hits=$(printf '%s\n%s\n' "$brace_hits" "$(tidy_hits "Always use {} for blocks")" \
    | grep -v '^$' | sort -u)

smell_out=$(refactor.smell --porcelain $files 2>"$work/smell.err")
smell_status=$?
smell_skipped=""
if [ "$smell_status" -gt 1 ]; then
    smell_skipped=$(sed 's/^refactor: refused - //' "$work/smell.err")
    smell_out=""
fi

smell_rows() {
    printf '%s\n' "$smell_out" | CORE="$core_purpose_api" awk -F'\t' -v RULE="$1" -v KIND="$2" '
        BEGIN {
            split(ENVIRON["CORE"], declared, "\n")
            for (i in declared) { if (declared[i] != "") { core[declared[i]] = 1 } }
        }
        $1 != RULE { next }
        {
            key = $2
            sub(/\(\).*$/, "", key)
            sub(/:[0-9]+:/, ":", key)
            kind = "H"
            if (key in core) { kind = "X" }
            if (kind == KIND) { print $2 }
        }
    '
}

tiny_hits=$(smell_rows wrappers H | only_added \
            | awk '{ sub(/ \|\|CMD\|\| /, "\n      "); print }')
tiny_exempt=$(smell_rows wrappers X | only_added)
accessor_hits=$(smell_rows accessors H | only_added)

smallclass_hits=$(awk -F'\t' '
    $4 == 1 && $7 == 0 && $9 == 0 && $6 == 0 && $5 > 0 && $5 == $8 {
        printf "%s:%d:%s adds nothing to its base - a constructor, no overrides, no members; dissolve it into its call site\n", $1, $2, $3
    }
    $4 == 0 && $9 == 0 && $5 >= 1 && ($5 + $6) <= 2 {
        printf "%s:%d:%s holds %d function(s) and %d member(s) - too small to be its own class; dissolve it unless you can say what it owns\n", $1, $2, $3, $5, $6
    }
' "$classes" | only_added | KEPT="$kept_small_classes" awk -F':' '
    BEGIN { n = split(ENVIRON["KEPT"], kept, "\n"); for (i = 1; i <= n; i++) { if (kept[i] != "") { keep[kept[i]] = 1 } } }
    { split($3, name, " "); if (!(($1 ":" name[1]) in keep)) { print } }
')

enum_hits=$(echo "$files" | xargs awk '
    function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        return s
    }
    {
        line = $0
        sub(/\/\/.*$/, "", line)

        if (line ~ /^[[:space:]]*(mutable[[:space:]]+)?(std::atomic<bool>|bool)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*([Tt]ype|[Mm]ode|[Kk]ind|[Ss]tate|[Ss]tyle)[A-Za-z0-9_]*[[:space:]]*[=;]/) {
            printf "%s:%d:%s - names a mode but holds it in a bool; give the states names in an enum\n", FILENAME, FNR, trim($0)
            next
        }
        if (FILENAME ~ /\.h$/ \
         && line ~ /^[[:space:]]*(int|juce::String)[[:space:]]+[A-Za-z_]*([Tt]ype|[Mm]ode|[Kk]ind|[Ss]tyle)[A-Za-z0-9_]*[[:space:]]*[=;]/) {
            printf "%s:%d:%s - carries a kind in an untyped field; name the alternatives in an enum\n", FILENAME, FNR, trim($0)
        }
    }
' 2>/dev/null | only_added)

emit "Never use inline functions"                                        "$inline_hits"
emit "Never use ternary operators"                                       "$ternary_hits"
emit "This project uses no code comments"                                "$comment_hits"
emit "Always use {} for blocks"                                          "$brace_hits"
emit "Never write 1-2 line functions, wrappers, or single-operation functions" "$tiny_hits"
emit "Anything that needs a getter belongs in public scope"              "$accessor_hits"
checked_labels=""
while IFS=$'\x1f' read -r check_rule check_label check_paths check_in_functions check_skip check_pattern; do
    if [ -z "$check_rule" ]; then
        continue
    fi
    checked_labels="${checked_labels}, ${check_label}"
    check_files=$(echo "$files" | tr ' ' '\n' | grep -E "^${check_paths}" || true)
    if [ -z "$check_files" ]; then
        continue
    fi
    check_hits=$(echo "$check_files" | PATTERN="$check_pattern" SKIP="$check_skip" INFUNC="$check_in_functions" xargs awk -F'\t' '
        FILENAME == ARGV[1] { if ($1 == "F") { for (l = $3; l <= $4; l++) { fn[$2 ":" l] = $8 } } ; next }
        {
            if (ENVIRON["INFUNC"] == "1") {
                owner = fn[FILENAME ":" FNR]
                if (owner == "") { next }
                if (ENVIRON["SKIP"] != "" && owner ~ ENVIRON["SKIP"]) { next }
            }
            line = $0
            sub(/\/\/.*$/, "", line)
            if (line ~ ENVIRON["PATTERN"]) { printf "%s:%d:%s\n", FILENAME, FNR, $0 }
        }
    ' "$funcs" 2>/dev/null | only_added)
    emit "$check_rule" "$check_hits"
done <<< "$project_checks"
emit "Very small classes should be dissolved, not kept"                  "$smallclass_hits"
emit "Named states and kinds belong in an enum, not a bool or a bare int" "$enum_hits"

checked="inline, ternaries, comments, braces (text plus clang-tidy AST), forwarding-call wrappers (clang AST), very small classes, accessors over non-public fields (clang AST)${checked_labels}, modes and kinds held outside an enum"
unchecked="Code fits the class's intended purpose / single area of concern
Avoid encapsulation on very small segments of code which repeat"
if [ -n "$project_unchecked" ]; then
    unchecked="${unchecked}"$'\n'"${project_unchecked}"
fi
unchecked="${unchecked}
Prefer declaring an unused variable over deleting one that represents the class's functionality
Whether a short function qualifies for the \"states a larger process\" exception - ASK, do not self-certify
Whether a small function is the class's core purpose - if so it belongs in core_purpose_api under [suite] in .claude/refactor.toml, and ASK before adding it
Whether a class small enough to flag has a reason to exist anyway - ASK before keeping it
Whether several bools in one class are really one enum state - the enum check only sees a field named like a mode, so a cluster such as brushStrokeActive/brushErase passes it
Whether a state named in neither the type nor the field name still has two or more named alternatives and so owes an enum"

if [ -n "$smell_skipped" ]; then
    report="${report}"$'\n'"[SKIPPED] Wrappers and accessors were NOT checked - ${smell_skipped}"$'\n'
fi

if [ -n "$tiny_exempt" ]; then
    report="${report}"$'\n'"[EXEMPT] Small functions declared as their class's core purpose (core_purpose_api in .claude/refactor.toml)"$'\n'"$(printf '%s\n' "$tiny_exempt" | sed 's/^/  /')"$'\n'
fi

coverage="design-rules: machine-checked - ${checked}"$'\n'
coverage="${coverage}design-rules: NOT machine-checked - judge these yourself, a pass here is not a pass on them:"$'\n'
coverage="${coverage}$(printf '%s\n' "$unchecked" | sed 's/^/  /')"

case "$mode" in
    post-tool)
        if [ "$violations" -eq 0 ]; then
            exit 0
        fi
        context="Design-rule violations in ${target} (CLAUDE.md Key Design Rules)."$'\n'
        context="${context}Fix the ones this edit introduced now, in this turn, before moving on."$'\n'
        context="${context}If a hit is pre-existing code you only touched, leave it and say so."$'\n'
        context="${context}${report}"$'\n'"${coverage}"
        jq -n --arg ctx "$context" \
          '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'
        exit 0
        ;;
    stop)
        if [ "$violations" -eq 0 ]; then
            exit 0
        fi
        reason="Design-rule violations remain in files changed vs HEAD (CLAUDE.md Key Design Rules)."$'\n'
        reason="${reason}Fix the ones you introduced this session."$'\n'
        reason="${reason}For any hit that is pre-existing code you only touched, leave it and report it to the user."$'\n'
        reason="${reason}${report}"$'\n'"${coverage}"
        jq -n --arg r "$reason" '{decision: "block", reason: $r}'
        exit 0
        ;;
    *)
        echo "design-rules: checking $scope"
        echo "$files" | sed 's/^/  /'
        printf '%s' "$report"
        echo
        if [ "$violations" -eq 0 ]; then
            echo "design-rules: no violations of the machine-checked rules"
        else
            echo "design-rules: $violations rule(s) violated"
        fi
        echo "$coverage"
        if [ "$violations" -eq 0 ]; then
            exit 0
        fi
        exit 1
        ;;
esac
