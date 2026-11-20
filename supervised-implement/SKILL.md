---
name: supervised-implement
description: Implement a plan or idea note together with the user, one reviewed edit at a time. Use when the user wants to supervise the implementation, says "implement this with me", "supervised", "pair on this", or invokes /supervised-implement.
---

The user reviews every design decision before it reaches a file. Speed is
not the goal; a codebase the user understands and agreed to is.

## Session start

1. Read the note(s) named by the user and any comments or questions file the user
   keeps next to them (treat those as constraints).
2. Enter plan mode. The plan is high-level and fits on one screen: the
   units in order (a unit is one commit), what quantity each unit's test
   compares against what, the result directory, and the open decisions
   the note leaves. It does NOT fix signatures, saved schemas, tolerances
   or constants; those are Tier-A proposals inside the unit they belong
   to, so the user reviews them once, with the code in front of them.
3. Resolve the open decisions with the user before writing code. For each,
   give a recommendation and the alternative you rejected. Use the
   `interrogate-me` skill if there are more than three.
4. The approved plan is the unit list for the session. Re-enter plan mode
   only if a unit turns out to need a different decomposition.

## Two tiers of edits

**Tier A — propose in chat first, apply only after the user reacts.**
Anything that fixes an interface or a quantity the experiment depends on:

- a new module, file, or result directory
- a public function signature or CLI flag
- the schema of what a driver saves (`.npz` keys, CSV columns)
- the oracle formula, the test's tolerance, and any numerical constant
  (grid sizes, ridge, seeds, MC budgets)
- anything inside the project's core package (as named in CLAUDE.md or the plan)
- sbatch resources, or deleting / renaming anything

**Tier B — apply directly through the permission prompt.** Edits inside a
function body whose signature was already agreed, docstrings, imports,
plotting cosmetics, fixing a failing test without changing an interface.

When in doubt, it is Tier A.

## Proposal format (Tier A)

- One proposal per message. Never bundle two Tier-A items.
- One to three lines first: what this decides, why this way, what
  alternative was rejected. Then the code in a fenced block, at most
  about 40 lines. If it does not fit, split the unit.
- Stop and wait. Do not work ahead on the next unit while a proposal is
  pending, and do not touch files in the meantime.
- After the user reacts, apply exactly what was agreed. If implementing
  reveals the agreement does not work, say so and re-propose; never
  deviate silently.

## Order within a unit

1. The oracle test (Tier A). The user reviews the test before the
   implementation exists.
2. The implementation, in Tier-A / Tier-B pieces.
3. Run the test (as the project's CLAUDE.md says; show the command first).
4. Commit the unit: on the working branch, only the unit's files, message
   names the unit.

## Pacing

Say at the start of each unit what it is and roughly how many proposals
it will take. Predict the runtime of any sbatch job before launching it.
Report test output verbatim when it fails.
