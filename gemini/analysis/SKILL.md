---
name: analysis
description: How to write a program audit (inward, findings about this codebase) or research report (outward, external research mapped back onto the codebase) into .claude/context/GeminiAnalysis/Unreviewed. Use whenever asked to audit, analyze, critique or research the codebase, its architecture, or its use of its frameworks and tooling.
---

# Analysis — writing program audits and research reports

This is stage one of three. You write a report; Claude reviews it as your advisor, checking every claim against the code and marking it Confirmed, Corrected, Stale, Refuted or Unverified; then the proposal stage turns the surviving findings into a plan of action. **Only what survives review reaches the code.** A report is worth the number of important findings that survive, not its length.

Everything here applies the analyst brief's §3 (evidence, judgment, respect for the project's rules) and the project profile. This skill is the procedure.

## 0. Choose the report type

| | Program audit | Research report |
|---|---|---|
| Direction | Inward: this codebase | Outward: other systems, frameworks, literature |
| Question it answers | What is wrong, fragile or under-used *here*? | How do others solve this, and what does that mean *here*? |
| Primary source | The code at `HEAD` | Framework source, docs, papers, talks, other engines' code |
| Folder | `Unreviewed/ProgramAudits/` | `Unreviewed/ResearchReports/` |

If a task needs both, write two reports: the research report first, then an audit that cites it. A report that mixes them gets reviewed as neither.

## 1. Prepare

1. **Read the project's CLAUDE.md (`.claude/CLAUDE.md` or `CLAUDE.md`) in full.** It is the authoritative architecture, and it holds the model invariants and Project Design Rules you will be judged against, alongside the Key Design Rules.
2. **Read `.claude/context/GeminiAnalysis/Reviewed/`.** For each review, read the *Critique* (what you did wrong last time) and the *Questions for the Author* (your open assignments). Don't raise a reviewed finding again as new.
3. **Read `.claude/context/Proposals/` and the project's issues file** (`issues_file` in `.claude/refactor.toml`, default `.claude/notes/ongoing-issues.md`), if it keeps one. A problem that already has a proposal or an entry is covered. Reference it; don't rediscover it.
4. **Record the commit:** `git rev-parse --short HEAD`. Every `file:line` in your report is at that commit.
5. **Fix the scope.** Write down in one or two sentences what the report covers, such as a subsystem, a mechanism or a question, and what it deliberately leaves out. A narrow report that is fully verified beats a broad one that is half verified.

## 2a. Program audit — the procedure

Work subsystem by subsystem inside your scope. For each one:

1. **Map it before judging it.** List the classes and their owners, the public API and its callers, and which thread each part runs on. Trace data from its entry point (the main loop, a callback, an event handler) through to its effect. Keep notes on how it works; the review will test whether you understood it.
2. **Check it against the model invariants** that the project's CLAUDE.md and the profile state. For each one that touches your scope, check every instance of the mechanism it constrains, and name the call path for any claimed violation.
3. **Check the gap between CLAUDE.md and the code.** Where the documentation says one thing and the code does another, report which is wrong.
4. **Check framework and tooling leverage.** Look for hand-rolled code that the frameworks and language version the profile names already provide, and for framework features used incorrectly. Confirm that every facility you name exists by reading its header or the standard. Tooling includes the project's test suite and the read-only `refactor.smell` / `refactor.find` commands.
5. **Gather evidence mechanically where you can:**
   - `refactor.find function 'numlines > 80' <path>` for oversized functions;
   - `refactor.find repeating 'numlines > 3' <path>` and `refactor.find repeating shape 'numlines > 3' <path>` for duplication. Start low; adjacent short findings in the same two files may be one duplicate;
   - `refactor.smell <path>` for wrappers and accessors;
   - the test targets (`test_targets` in `.claude/refactor.toml`) to check whether a behaviour is already covered.
6. **Before you write a finding down, re-read its site** and confirm the line number at your recorded commit.

## 2b. Research report — the procedure

1. **Start from a question about this codebase**, not a topic. "How do established systems do X, and does our class that does X match?" is a research question. "X in general" is a topic, and it produces a survey that lands nowhere.
2. **Establish how the project does it now,** with `file:line`, before reading anything external. You can't compare against something you haven't pinned down.
3. **Collect primary sources:** framework and comparable systems' source code (the profile names the relevant ones), official documentation, papers, and talks by the people who built the systems. Prefer reading an engine's actual source over a description of it. Note the version of everything you cite.
4. **Compare like with like.** For each external approach, state the problem it solves, the constraints it was built under (language, threading model, deployment), and whether those constraints hold here. An approach built for a multi-process server doesn't transfer to a single plugin just because it is well regarded.
5. **Land every conclusion on the codebase.** Each section ends with *what this means here*: the specific file or mechanism, what it does differently, and whether the difference costs anything. If it costs nothing, say so. "The project already does this well" is a valid, useful result.
6. **Promote actionable conclusions:** any conclusion that implies a change also becomes an item in `Unreviewed/ProgramAudits/gemini complaints.md`, which cites the research report.

## 3. Writing each finding

Every finding in either report type uses this shape:

```
### [P1] Short statement of the defect or opportunity
- Where: Source/Audio/Foo.cpp:120 — `Foo::bar` (at <commit>)
- Kind: code fact | inference | external comparison
- Confidence: verified | traced | suspected
- What happens: the mechanism step by step, and a concrete input that exposes it
  (the profile says what inputs mean for this project)
- Why it matters: the invariant, goal or user-visible behaviour it breaks
- Evidence: the call path, test, tool output or measurement, and external sources with links and versions
- Settles it: for anything below "verified", the test, sanitizer run or measurement that would confirm or refute it
- Recommendation: the change, shown to be writable under the Key Design Rules
- Cost: files touched, risk, and what it buys
```

- **Confidence levels.** *Verified* means you read the code and it does this. *Traced* means you followed the mechanism end to end but didn't run it. *Suspected* means a pattern worth checking, with a *Settles it* line. Honest confidence survives review; overstated confidence gets refuted.
- **Priority** follows the brief's §3: P0 incorrect output, crashes or real-time and threading violations; P1 broken invariants or architecture blocking growth; P2 framework under-use with a concrete payoff; P3 polish.
- **Recommendations follow the Key Design Rules and the Project Design Rules.** A recommendation must be writable with no comments, no ternaries, no wrapper functions, no getters or setters, enums for named states, no namespaces, and within the project's own rules. If you think a rule itself causes harm, argue that in a separate section titled *On the Project's Rules*, with evidence from this codebase. Never list a rule as a defect.

## 4. Report layout

```
# <Title that states the question or scope>

> Type: Program audit | Research report
> Written <YYYY-MM-DD> at <commit>. Scope: <one or two sentences, including what is out of scope>.
> Answers: <the reviews' Questions for the Author this report addresses, if any>

## Summary
The top findings in priority order, one line each, with file:line.

## How It Works Now
Your map of the subsystems in scope: owners, API, threads, data flow. Short, but specific.

## Findings            (program audit)
## Research           (research report: one section per external system or question,
                       each ending in "What this means here")

## On the Project's Rules     (optional, only with evidence)

## Sources             (research report: every external source, linked, with version)
```

Name the file for its topic in `snake_case` and put it in the matching `Unreviewed/` subfolder.

## 5. Before you submit, review yourself

Run the advisor's checks on your own report:

- Re-open every `file:line`. Does the code there still say what you claim, at your recorded commit?
- For every finding about an invariant, did you check every instance of the mechanism it constrains?
- For every real-time or threading finding, did you name the call path from its entry point?
- For every framework or language facility you recommend, did you confirm it exists in the version the profile names?
- Is every recommendation writable under the Key Design Rules and the Project Design Rules?
- Is anything already in `Reviewed/`, `Proposals/` or the issues file?
- For a research report, does every section end on a specific file here?
- Cut every finding that would come back **Refuted** or **Stale**, and every sentence that makes no claim.
