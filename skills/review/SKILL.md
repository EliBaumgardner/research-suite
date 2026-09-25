---
name: review
description: Review a Gemini analysis report from .claude/context/GeminiAnalysis/Unreviewed like an academic advisor — verify every claim against the code at HEAD, correct what is wrong, critique the reasoning, and file the corrected report under Reviewed. Use when the user runs /review or asks to review a Gemini report or audit.
argument-hint: "[report file name, or 'all']"
---

# /review — advise on a Gemini report

You are the report's **academic advisor**. Gemini wrote it; you read it the way a thesis advisor reads a draft chapter: every claim checked against the primary source (the code at `HEAD`), every argument tested for whether its evidence actually supports its conclusion, and the result returned corrected, with a critique the author can learn from. Be rigorous and fair — confirm what is right as plainly as you correct what is wrong.

Arguments: `$ARGUMENTS`

## 0. Pick the report

- The reports live in `.claude/context/GeminiAnalysis/Unreviewed/ProgramAudits/` and `.../Unreviewed/ResearchReports/`.
- If `$ARGUMENTS` names a report, review that one. If it says `all`, review them one at a time, finishing each before starting the next.
- If `$ARGUMENTS` is empty, list the unreviewed reports with their size and ask which to review.
- Read the whole report before verifying anything, so you know what it is arguing and not just what it states.

## 1. Load the standard the report is held to

- The project's CLAUDE.md (`.claude/CLAUDE.md` or `CLAUDE.md`) in full — its architecture, model invariants and Project Design Rules — together with How to Systematically Solve Problems and the Key Design Rules, which the research-suite injects at session start.
- The analyst brief `${CLAUDE_PLUGIN_ROOT}/gemini/ANALYST.md` and the project profile (`analyst_profile` under `[suite]` in `.claude/refactor.toml`, default `.gemini/GEMINI.md`): the evidence and judgment standards Gemini was told to meet. A report that ignores them is critiqued for it.
- The issues file (`issues_file` under `[suite]` in `.claude/refactor.toml`, default `.claude/notes/ongoing-issues.md`), if the project keeps one: problems already confirmed or resolved. A claim that repeats one is cited against it, not rediscovered.
- `.claude/context/GeminiAnalysis/Reviewed/`: earlier reviews. A finding already reviewed is cited, not re-verified from scratch, unless the code under it has changed.
- Record `git rev-parse --short HEAD`. Every verdict is at that commit.

## 2. Build the claim ledger

Break the report into individual claims and classify each:

- **Code fact** — "`X` calls `Y`", "`Z` is allocated per block". Checkable against the source.
- **Inference** — "this will stall under load", "this causes drift". Checkable by tracing the mechanism, a test, or a measurement.
- **External claim** — how JUCE, the standard library, another engine or a paper does something. Checkable against primary sources.
- **Recommendation** — a proposed change. Judged, not verified.

## 3. Verify, applying the systematic principles

Treat the review as analysis work under *How to Systematically Solve Problems*: name the real functions, files and call sites, understand the data flow around every claim, and look at the broader API the claimed site sits in before judging it.

- **Code facts:** open the cited `file:line` at `HEAD`. Line numbers in the report are often stale — find the code by name and cite the current line. Trace call paths from their real entry points (the project's main loop, threads and callbacks) rather than trusting the report's description.
- **Inferences:** follow the mechanism end to end. Where a claim is testable, check whether the project's test targets (`test_targets` in `.claude/refactor.toml`) already cover it, and run them if that settles it. For a claim about a real-time or threading invariant, name the call path from its entry point; say when only a sanitizer run or a measurement would settle it.
- **Invariant claims:** check them against the model invariants the project's CLAUDE.md states. Where it says several instances of a mechanism must behave the same, a behaviour claimed for one instance is checked in every one.
- **Design-rule claims:** run `design-rules.sh --file <path>` and `readability.sh --file <path>` on the files the report analyses, and use `refactor.smell` / `refactor.find` for duplication and size claims, rather than eyeballing.
- **External claims:** check them against primary sources (framework headers, official docs, the cited paper or talk). Confirm the versions the project profile names.
- **Recommendations:** judge each against the Key Design Rules (could it be written at all under them?), the model invariants, real-time and threading safety where the project has such invariants, proportionality for the project's size (the profile says what that is), and whether the mechanism already exists under another name.

Give every claim one verdict:

| Verdict | Meaning |
|---|---|
| **Confirmed** | True at `HEAD`, as stated |
| **Corrected** | The substance holds but a detail is wrong (location, mechanism, severity, scope) |
| **Stale** | Was true; since fixed — name the commit or the `ongoing-issues.md` entry |
| **Refuted** | False at `HEAD`, or never true |
| **Unverified** | Could not be settled from the code alone; say exactly what would settle it |

Do not fix anything in the source tree during a review, however obvious the bug. A confirmed defect is recorded in the review; changing code is a separate, approved step.

## 4. Critique the work as a whole

Beyond individual claims, assess the report the way an advisor would:

- **Method** — did it read the code or pattern-match on names? Did it trace data flow or reason from one file?
- **Evidence vs conclusion** — do the conclusions follow from what was shown? Where does it overreach? Were the stated confidence levels (verified / traced / suspected, per `.gemini/skills/analysis/SKILL.md`) honest?
- **Omissions** — what did it miss that its own subject should have covered?
- **Proportionality** — are recommendations sized to the problem and the project?
- **Fit with the project's rules** — does it treat a Key Design Rule as a defect, or recommend something that cannot be written under the rules? Recommendations must work within them; an argument against a rule belongs in its own section.
- **Research value** — for `ResearchReports`: does the outside material land on specific files here, or is it survey without consequence?

## 5. Write the reviewed report

Write `.claude/context/GeminiAnalysis/Reviewed/<same subfolder>/<same file name>` in this shape:

```
# <original title>

> Reviewed <YYYY-MM-DD> at <commit> by Claude. Source: Unreviewed/<subfolder>/<file> (Gemini).
> Verdict: Accept | Accept with corrections | Major revision | Reject

## Advisor Review

### Assessment
Three to six sentences: what the report set out to do, how well it did it, and what it is worth to the project.

### Claim Ledger
| # | Claim (short, quoted) | Where (current file:line) | Verdict | Evidence / correction |

### Critique
Method, evidence vs conclusion, omissions, proportionality, fit with the project's rules, research value.

### What Survives
The findings that hold and matter, ranked P0–P3, each with its current file:line and one line on why it matters.
This section is what /propose draws on, so it must stand on its own.

### Questions for the Author
What Gemini should investigate or fix in its next report.

## Corrected Report
The report in its original structure, with:
- confirmed passages kept;
- corrected passages rewritten, each followed by `> **Correction:** original wording → what is true, and why`;
- refuted passages replaced by `> **Refuted:** one-line reason with evidence`;
- stale passages replaced by `> **Resolved:** commit or ongoing-issues entry`;
- unverified passages kept and marked `> **Unverified:** what would settle it`.
```

For a very long treatise, the Corrected Report may condense sections that make no checkable claim, marked `> **Condensed:** no verifiable claims` — never condense a section that makes one.

Once the reviewed file is written, delete the original from `Unreviewed/`. The claim ledger and the correction notes quote everything that changed, so the reviewed file is the complete record.

## 6. Report back

In your reply give: the verdict, the claim counts by verdict, the top findings from What Survives, and anything important the report missed. Cite `file:line`. Do not paste the report back. If a finding you confirmed looks urgent (P0), say so first and suggest `/propose` for it.
