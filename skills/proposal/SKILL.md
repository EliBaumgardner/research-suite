---
name: proposal
description: Turn findings from reviewed analysis (.claude/context/GeminiAnalysis/Reviewed) into a detailed, step-by-step plan of action written to .claude/context/Proposals/Unimplemented. Use when the user runs /propose or asks for a proposal or implementation plan based on a reviewed report.
argument-hint: "[reviewed report, finding, or topic]"
---

# /propose — a plan of action from reviewed analysis

A proposal turns what a review established into a plan the owner can approve and Claude can then carry out step by step. It is judged on one thing above all: **does it show a complete, correct understanding of the problem** — the mechanism, the code it lives in, the data that flows through it, and every consequence of changing it. A plan built on a shallow understanding is worse than no plan.

You write the proposal. You do **not** change any code while writing it. Implementation happens later, one approved step at a time.

Arguments: `$ARGUMENTS`

## 0. Choose what the proposal addresses

- Proposals draw only on **reviewed** analysis: the *What Survives* sections of reports in `.claude/context/GeminiAnalysis/Reviewed/ProgramAudits/` and `.../Reviewed/ResearchReports/`. Never build a proposal on an unreviewed report — if the user points at one, say it needs `/review` first.
- If `$ARGUMENTS` names a reviewed report, a finding, or a topic, find the surviving findings it covers. Several findings that share a root cause belong in one proposal; unrelated findings belong in separate ones.
- If `$ARGUMENTS` is empty, list the surviving findings across all reviewed reports with their priority, mark the ones already covered by a file in `.claude/context/Proposals/Unimplemented/` or `.../Implemented/`, and ask which to propose.
- Check `.claude/context/Proposals/Unimplemented/` and `.../Implemented/` for an existing proposal on the same problem. Extend or supersede an unimplemented one; do not write a duplicate. A problem an implemented proposal already addressed is proposed again only if the review shows that fix fell short, and the new proposal cites it.
- Check the issues file (`issues_file` under `[suite]` in `.claude/refactor.toml`, default `.claude/notes/ongoing-issues.md`), if the project keeps one: an issue already resolved there is not proposed again.

## 1. Understand the problem completely

Apply *How to Systematically Solve Problems* in full, against the code at `HEAD` — the review verified the finding at an earlier commit, so re-read every site now. Record `git rev-parse --short HEAD`.

- **API surface** — every function, type and member the problem touches, and every caller of each (use clangd / `refactor.find`, not memory).
- **Structure** — which classes own the pieces, how they are composed, and which part of the architecture the project's CLAUDE.md assigns each to.
- **Data flow** — how data reaches the problem site and where it goes after: which thread, which callback, which shared state.
- **Mechanism** — step by step, how the defect or missed opportunity actually arises, with a concrete input that exposes it.
- **Broader API** — the classes that compose the ones involved, and the design they follow. Repeat the pass one level up.
- **Invariants touched** — which of the model invariants the project's CLAUDE.md states the problem or the fix touches.

If the finding turns out to be wrong or already fixed at `HEAD`, stop and say so instead of proposing.

## 2. Decide the approach

- Lay out the realistic approaches, not every conceivable one. For each: what it changes, what it costs, what it risks, and whether it can be written under the Key Design Rules.
- Recommend one, and say why.
- **Where the problem maps onto several mechanics or several reasonable designs, do not choose silently** — put the choice in *Decisions for the Owner*. The same goes for anything the rules say to ask about first: a new short function that "names a larger process", a new `core_purpose_api` entry, or any deviation from a rule. A proposal that needs one lists it as a decision; it never plans it as settled.

## 3. Write the proposal

Write `.claude/context/Proposals/Unimplemented/<snake_case_topic>.md` in this shape:

```
# <Proposal title>

> Status: Draft | Approved | In progress | Implemented | Superseded
> Written <YYYY-MM-DD> at <commit>. Sources: Reviewed/<subfolder>/<file> (findings #…), …

## Summary
Three to five sentences: the problem, why it matters, the recommended fix, and its size.

## The Problem
### Mechanism
Step by step, with real functions and file:line, how the problem arises. Include the concrete input that exposes it.
### Evidence
What confirms it: the review's ledger entries, code read at HEAD, a test that fails or a test that would.
### Why It Matters
The consequence for the project's users, and the invariant or goal it breaks. Priority P0–P3.

## Current Design
### API Surface
Every function, type and member involved, with its callers.
### Structure
Owners and composition, and the directory responsibility each piece falls under.
### Data Flow
The path through threads, callbacks and shared state, as a short diagram if it helps.

## Approaches Considered
Each realistic approach: what it changes, cost, risk, fit with the Key Design Rules. Then the recommendation and why.

## Plan
Numbered steps, ordered so the minimal fix lands first and cleanups follow. Every step leaves the tree building and the tests passing. For each step:

### Step N — <name>
- **Goal:** what this step achieves on its own.
- **Changes:** files, functions and members, and exactly what changes in each. Code sketches, where given, follow the Key Design Rules (no comments, no ternaries, braces on every block, no wrappers, enums for named states).
- **Refactor commands:** any extract, inline or rename done with `refactor.encap` / `refactor.decap` / `refactor.replace`, and any multi-site mechanical rewrite with `refactor.rewrite`, named with its arguments.
- **Behaviour delta:** for each class of input the code handles, what it does before and after. Any difference not required by the goal is called out.
- **Invariants:** for anything the project's invariants constrain (a real-time path, a thread boundary, an ownership rule), why the step keeps them.
- **Verification:** the build target and test targets from `.claude/refactor.toml`, the new or changed test (including any test the project's CLAUDE.md requires for this kind of change), and the manual check, with what to look for.
- **Rollback:** how to back the step out on its own.

## Risks
What could go wrong, how likely, how it would show up, and how the plan guards against it.

## Out of Scope
Related problems deliberately left for another proposal, and why.

## Decisions for the Owner
Every open choice, with the options and your recommendation. Implementation does not start until these are answered.
```

Depth is the point. Name the real functions at every step; a step that says "update the listener" without saying which listener, which callback and what it does differently is not finished.

## 4. Report back

In your reply give the proposal's path, its summary, the number of steps, and the *Decisions for the Owner* as questions. Do not start implementing. When the owner approves, set the Status line to `Approved`; implementation is `/implement`'s job, which verifies the proposal once more before building it.
