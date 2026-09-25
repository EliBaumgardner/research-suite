# research-suite

A Claude Code plugin for C++ projects:

- **Gates**: hooks that check every edit against a set of design and readability rules, and a `-deep` mode that makes Claude state and defend a systematic pass over the code it touches.
- **The research pipeline**: Gemini audits the codebase or researches outside it, Claude reviews the report like an academic advisor, turns what survives into a step-by-step proposal, and implements an approved proposal.

The plugin holds no project's data. Every project keeps its own reports, proposals, config and rules; the plugin creates the folders for them.

## Install

```bash
claude plugin marketplace add EliBaumgardner/research-suite
claude plugin install research-suite@research-suite --scope project
```

Install at project scope: the hooks run in every project the plugin is enabled in. Then run `/research-suite:init` in the project.

To work on the plugin from a local clone, add the clone as the marketplace instead (`claude plugin marketplace add ~/path/to/research-suite`). Hooks run a cached copy, so after changing the plugin bump `version` in `.claude-plugin/plugin.json` and run `claude plugin update research-suite@research-suite --scope project`.

## Requirements

- `jq` and `python3` (3.11 or later)
- [`refactor-tools`](https://github.com/EliBaumgardner/refactor-tools): clone it and `pip install -e refactor-tools` (its README has the LLVM requirements). The gates read the project config through it, use its C++ scanner, and call `refactor.smell` and `refactor.tidy`.
- `agy` (Antigravity) for the analysis stage, and the `claude` CLI for the review and proposal stages

## Commands

| Command | What it does |
|---|---|
| `/research-suite:init` | Creates the context folders, `.claude/refactor.toml` and the analyst profile in this project, then helps fill them in |
| `/research-suite:research <subject>` | Runs analyze → review → propose in the background |
| `/research-suite:review [report]` | Reviews one Gemini report and files it under `Reviewed/` |
| `/research-suite:propose [report or topic]` | Writes a proposal from reviewed findings |
| `/research-suite:implement [proposal]` | Verifies an approved proposal, builds it step by step, files it under `Implemented/` |

`bin/` is on the Bash tool's `PATH` while the plugin is enabled, so the gates run as bare commands: `design-rules.sh --all`, `readability.sh --file <path>`, `research-init`.

## What lives where

**In the plugin**

```
bin/                 the gates, the rules hook and research-init
lib/project.sh       reads the project config for every gate
rules/               How to Systematically Solve Problems and the Key Design Rules
hooks/hooks.json     SessionStart, UserPromptSubmit, PreToolUse, PostToolUse and Stop hooks
skills/              init, research, review, proposal (with the propose command), implement
gemini/              the analyst brief, the analysis procedure and the prompt template
```

**In each project**

```
.claude/refactor.toml       the one config, shared with refactor-tools
.claude/CLAUDE.md           architecture, invariants and a "### Project Design Rules" section
.gemini/GEMINI.md           the analyst profile: frameworks, invariants, comparable systems
.claude/context/
├── GeminiAnalysis/
│   ├── Unreviewed/{ProgramAudits,ResearchReports}/   Gemini writes here
│   └── Reviewed/{ProgramAudits,ResearchReports}/     review writes here
└── Proposals/
    ├── Unimplemented/                                propose writes here
    └── Implemented/                                  implement files here
```

## Configuration

Everything the suite reads is under `[suite]` in `.claude/refactor.toml`, next to the keys `refactor-tools` already uses (`sources`, `build_target`, `test_targets`, ...). Every key is optional.

```toml
[suite]
core_purpose_api   = ["src/Bridge.h:push"]     # small functions that are their class's purpose
kept_small_classes = ["src/Data.h:Map"]        # small classes kept on purpose
disabled_rules     = []                        # rule names the design-rule gate skips
unchecked          = ["..."]                   # project items for the "not machine-checked" list
project_rules      = "### Project Design Rules"   # the CLAUDE.md heading injected with the rules
rules_file         = ".claude/CLAUDE.md"       # default: .claude/CLAUDE.md, else CLAUDE.md
analyst_profile    = ".gemini/GEMINI.md"
issues_file        = ".claude/notes/ongoing-issues.md"

[[suite.checks]]                               # project rules checkable by a regular expression
rule           = "Never allocate on the audio thread"
label          = "audio-thread allocation"     # shown in the gate's coverage line
paths          = "src/audio/"                  # optional path prefix
in_functions   = true                          # optional: only lines inside a function
skip_functions = "^(prepare|reserve)"          # optional: functions exempt from the check
pattern        = 'malloc\(|make_unique'        # awk regular expression
```

Source files are `.cpp` and `.h` under `sources`.

## The rules

At session start the SessionStart hook injects `rules/systematic.md`, `rules/style.md` and the project's `project_rules` section, so they are in context from the first prompt and again after compaction. The prompt hook repeats them when a prompt carries `-deep`.
