---
name: implement
description: Implement an approved proposal from .claude/context/Proposals/Unimplemented — first run a final verification that checks the proposal against the reviewed analysis it came from and the code at HEAD, then carry out its plan step by step, and file the finished proposal under Proposals/Implemented. Use when the user runs /implement or asks to implement a proposal.
argument-hint: "[proposal file name]"
---

# /implement — verify a proposal, then build it

A proposal is the plan; this skill is the only place it becomes code. It runs in two phases, and the second never starts until the first passes:

1. **Final verification** — an independent subagent re-reads the proposal against the reviewed analysis it was built from and against the code at `HEAD`, and says whether the plan still holds.
2. **Generation** — you carry out the plan, one step at a time, under the Key Design Rules.

Arguments: `$ARGUMENTS`

## 0. Pick the proposal

- Proposals waiting to be built live in `.claude/context/Proposals/Unimplemented/`. Finished ones live in `.claude/context/Proposals/Implemented/` and are never implemented again.
- If `$ARGUMENTS` names a proposal, use it. If it is empty, list the files in `Unimplemented/` with their Status line and title, and ask which to implement.
- If the named proposal is in `Implemented/`, say so and stop.
- Read the whole proposal before anything else.
- Its **Decisions for the Owner** must be answered before generation. If any are open, ask them now as questions (AskUserQuestion, one per decision, the proposal's recommendation first) and record the answers under that section before phase 1, so the verifier checks the plan the owner actually chose.

## 1. Final verification (subagent)

Spawn one `general-purpose` subagent with the Agent tool. It starts cold, so its prompt must carry everything it needs:

- the proposal's path, and the path of every source report its `Sources:` line names under `.claude/context/GeminiAnalysis/Reviewed/` (ProgramAudits or ResearchReports), plus any entries it cites from the project's issues file (`issues_file` under `[suite]` in `.claude/refactor.toml`, default `.claude/notes/ongoing-issues.md`);
- the owner's answers to the Decisions for the Owner;
- the commit the proposal was written at, and the instruction to verify at `HEAD` (`git rev-parse --short HEAD`, and `git log --oneline <written-at>..HEAD -- <files the plan touches>`);
- the instruction to read the project's CLAUDE.md (`.claude/CLAUDE.md` or `CLAUDE.md`) in full — its architecture, model invariants and Project Design Rules — and the general rules in `${CLAUDE_PLUGIN_ROOT}/rules/systematic.md` and `${CLAUDE_PLUGIN_ROOT}/rules/style.md` (*How to Systematically Solve Problems* and the Key Design Rules);
- that it is **read-only**: it edits no file, runs no refactor command, and may build and run the tests only to settle a claim;
- the checks and the reply format below, verbatim.

The verifier checks:

1. **Fidelity to the analysis** — every finding the proposal cites exists in that report's *What Survives* (not only in the Corrected Report or an unreviewed draft), with the same priority and mechanism. Anything the proposal adds beyond the findings is named.
2. **The problem still exists at `HEAD`** — each `file:line` in *Mechanism* and *API Surface* is re-read by name. A finding fixed since, or code moved or renamed, is reported with its current location.
3. **The API surface is complete** — callers of every function the plan changes, found with clangd, `refactor.find` or grep, not taken from the proposal. A caller the proposal missed is a finding.
4. **The plan is sound** — each step's changes, behaviour delta and invariant argument hold against the code now; every step leaves the tree building; a change of a kind the project's CLAUDE.md names a required test for carries that test.
5. **The plan can be written under the Key Design Rules** — every code sketch and every new function, class, enum or member is checked against each rule. A step that needs a new short function, a new `core_purpose_api` entry, or any rule deviation, without a recorded owner decision, is a finding.
6. **The decisions are reflected** — the plan's steps match the answers recorded under Decisions for the Owner.

The verifier replies in this shape, and nothing else:

```
Verdict: Proceed | Proceed with amendments | Blocked
HEAD: <commit>   Proposal written at: <commit>

## Findings
| # | Check (1–6) | Step | Location (current file:line) | Finding | Required amendment |

## Amendments
Exact changes to the proposal's text, step by step, that make it correct at HEAD.

## Blocking issues
Anything that makes the plan wrong or unbuildable as written, and what would unblock it.
```

When it returns:

- **Proceed** — go to phase 2.
- **Proceed with amendments** — apply the amendments to the proposal file, add a line `> Verified <YYYY-MM-DD> at <commit>; amended: <one-line summary>` under its header, show the owner what changed, and continue only once they accept.
- **Blocked** — report the blocking issues and stop. Do not generate anything. The proposal stays in `Unimplemented/`; if it needs rewriting, that is `/propose`'s job.

Do not skip or shortcut this phase, even for a one-step proposal, and do not do the verification yourself in place of the subagent — its value is that it reads the proposal cold.

## 2. Generation

Set the proposal's Status line to `In progress`. Then, for each step of the Plan, in order:

1. **Explain before editing** — state the step's goal, the exact changes, and its behaviour delta, in a few lines. Do not edit until that is said.
2. **Make the changes** — extract, inline and rename through `refactor.encap` / `refactor.decap` / `refactor.replace`, and multi-site mechanical rewrites through `refactor.rewrite`, as the step names them; never by hand. Every new source file is registered with the build (for CMake, listed in `CMakeLists.txt`). The Key Design Rules bind every line: no comments, no ternaries, braces on every block, no wrappers, enums for named states, no accessors.
3. **Verify** — do what the step's *Verification* says: build the `build_target` and build and run the `test_targets` named in `.claude/refactor.toml` (in its `build_dir`), add the test the step names, and run `design-rules.sh --file <path>` and `readability.sh --file <path>` on every changed file. Build only into the project's existing build trees (`build_trees`); never configure a new one.
4. **Stop on surprise** — if the code does not match what the verified plan said, a test fails for a reason the step did not predict, or a step would need a rule deviation, stop and ask. Do not improvise a different fix, and do not flag a deviation in your report in place of asking.
5. **Report the step** — what changed (`file:line`), the build and test results as they came out, the manual check the step lists (which only the owner can run), and the added/removed line tally.

Pause after each step for the owner to continue, unless they have said to run all steps. Never commit unless asked.

## 3. File the proposal

When every step is done and verified:

- set the Status line to `Implemented`, and add `> Implemented <YYYY-MM-DD> at <commit or "uncommitted">.` under it;
- add an `## Implementation Notes` section at the end: per step, what was built, where it differed from the plan and why, and the manual checks still owed;
- move the file from `Proposals/Unimplemented/` to `Proposals/Implemented/` — it is removed from `Unimplemented/`, not copied;
- if the proposal resolves an entry in the project's issues file, mark it resolved there, citing the proposal.

If the work stops part-way, the proposal stays in `Unimplemented/` with Status `In progress` and an `## Implementation Notes` section recording which steps are done, so the next `/implement` resumes at the first unfinished step (phase 1 still runs, and verifies only the remaining steps).

## 4. Report back

Under headers: the verifier's verdict and any amendments, each step's result, the tests and gates as they ran, the manual checks the owner still needs to do, where the proposal was filed, and the total added/removed line tally.
