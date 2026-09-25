---
name: research
description: Run the whole research pipeline on one subject in the background — Gemini writes the audit or research report (/analyze), Claude reviews it (/review), then turns what survives into a proposal (/propose). Use when the user runs /research <subject>.
argument-hint: "<subject>"
disable-model-invocation: true
allowed-tools: Bash(*/skills/research/run-pipeline.sh *)
---

# /research — analyze, review and propose in one background run

Subject: `$ARGUMENTS`

This skill conducts the three stages of the research-suite pipeline (see the plugin's README). It does not do any stage itself. `run-pipeline.sh`, next to this file, runs each stage as its own process, so each one reads only what the stage before it filed:

1. `agy -p` on `gemini-3.1-pro-high` — Antigravity runs the prompt from the plugin's `gemini/analyze.toml`, with the subject, the analyst brief (`gemini/ANALYST.md`), the project profile (`analyst_profile` under `[suite]` in `.claude/refactor.toml`, default `.gemini/GEMINI.md`) and the analysis skill (`gemini/analysis/SKILL.md`) filled in, since Antigravity does not read `.toml` commands, and writes one new report into `GeminiAnalysis/Unreviewed/`. The script creates any missing context folder first, and stops if the project has no profile.
2. `claude -p "/research-suite:review <that report>"` — files the reviewed report in `GeminiAnalysis/Reviewed/` and deletes the original.
3. `claude -p "/research-suite:propose <the reviewed report>"` — writes the proposal(s) into `Proposals/Unimplemented/`.

Between stages the script checks that the stage wrote where it should and nowhere else. `git status` must be unchanged, and Gemini may touch nothing under `.claude/` or `.gemini/` outside `Unreviewed/`. On any failure it stops and reverts nothing. One subject per run; the pipeline never loops.

## 1. Launch

- If `$ARGUMENTS` is empty, ask for a subject and stop. Do not pick one.
- Run it with the Bash tool, `run_in_background: true`, from the project root:

  ```bash
  "${CLAUDE_PLUGIN_ROOT}/skills/research/run-pipeline.sh" <subject, quoted>
  ```

- Reply in one or two lines: the subject, that it is running in the background, and that you will report when it finishes. Do not wait on it, poll it or sleep. You are re-invoked when it exits.

## 2. When it exits

The script's output lists every step, starting with `logs: <run dir>`. That directory holds `summary.txt`, `analyze.log`, `review.log` and `propose.log`.

**On success**, read the reviewed report and each proposal it names, then report under headers:

- **Report** — the reviewed report's path and its `Verdict:` line.
- **Review** — claim counts by verdict from the Claim Ledger, and the top *What Survives* findings with `file:line`. Put any P0 first.
- **Proposal** — each proposal's path, its summary, and its number of steps.
- **Decisions for the Owner** — every one, as a question.

If no proposal was written, say why, quoting `propose.log` (for example, nothing survived review).

**On failure**, name the stage, quote the relevant lines of `summary.txt` and the tail of that stage's log, and say what was left on disk. For example, an unreviewed report that still needs `/review`, or files a stage wrote outside its folder. Do not revert anything, re-run a stage, or finish a stage by hand. The owner decides.

Do not start implementing anything a proposal describes.
