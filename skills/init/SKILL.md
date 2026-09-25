---
name: init
description: Set up the research suite in the current project — create the context folders, the .claude/refactor.toml config and the analyst profile, then help fill them in. Use when the user runs /research-suite:init or asks to set the research suite up in a project.
disable-model-invocation: true
allowed-tools: Bash(research-init)
---

# /init — set the research suite up in this project

## 1. Create what is missing

Run `research-init` from the project root with the Bash tool. It creates only what does not exist yet, and never overwrites:

- the context folders: `.claude/context/GeminiAnalysis/{Unreviewed,Reviewed}/{ProgramAudits,ResearchReports}/` and `.claude/context/Proposals/{Unimplemented,Implemented}/`;
- `.claude/refactor.toml`, the one config file the gates, the pipeline and `refactor-tools` share, with the source directory guessed;
- the analyst profile (`analyst_profile` under `[suite]`, default `.gemini/GEMINI.md`) as a skeleton.

It also reports whether the project's CLAUDE.md has a Project Design Rules section, and which tools are missing.

## 2. Fill them in

Read the codebase and its CLAUDE.md, then draft each of these and show it to the owner. Write a draft only once they accept it:

- **`.claude/refactor.toml`** — `sources`, `edit_roots`, `build_dir`, `build_trees`, `build_target` and `[test_targets]` from the project's real build. Never configure a new build tree to find out; read the build files.
- **The analyst profile** — each section of the skeleton, from what the code and CLAUDE.md actually say. Leave a section out rather than guess.
- **A Project Design Rules section** in the project's CLAUDE.md, under the heading `project_rules` names (default `### Project Design Rules`), if the owner has rules of their own beyond the Key Design Rules. Only rules the owner states; do not invent any.
- **`[[suite.checks]]`** entries, if a project rule can be checked by a regular expression. Each has `rule`, `label`, `pattern` (an awk regular expression), and optionally `paths` (a path prefix), `in_functions = true` and `skip_functions` (a function-name regular expression).

## 3. Report

List what was created, what was filled in, what the owner still needs to decide, and any missing tools with how to install them. Say that the research pipeline runs as `/research-suite:research <subject>`.
