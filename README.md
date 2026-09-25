# research-suite

Design-rule, readability and deep-mode gates for C++ projects, plus the analyze → review → propose → implement research pipeline, as a Claude Code plugin.

## Install

```bash
claude plugin marketplace add ~/Documents/GitHub/research-suite
claude plugin install research-suite@research-suite --scope project
```

Install at project scope: the hooks run in every project the plugin is enabled in.

## Commands

- `/research-suite:research <subject>` runs the whole pipeline in the background
- `/research-suite:review`, `/research-suite:propose`, `/research-suite:implement` run one stage

## Requirements

`jq`, `python3`, the `refactor-tools` suite on `PATH`, `agy` (Antigravity) for the analysis stage, and the `claude` CLI.
