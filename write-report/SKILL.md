---
name: write-report
description: Applies the house conventions for Markdown reports and notes saved to a file, namely YAML frontmatter (title, created, updated, authors, type), (H)/(C) author tags on sections, structure for experiment write-ups, notation and length. Use when creating or editing a report, note, write-up, summary or findings file (.md), when recording experiment results, or when the user says "write a report", "write this up" or "make a note".
---

## Project conventions come first

Before creating a file, check the repo's documentation (`CLAUDE.md`, a notes/docs
`README.md`, or similar) for:

- where this kind of note is stored and how files are named;
- the allowed `type` values and any section template for that type;
- any extra frontmatter fields it requires.

Where the repo says something, follow it over this skill. If it says nothing about
location, ask where the file should go; do not invent one. If it has no `type`
vocabulary, omit `type`; do not invent slugs. Never hard-code a path from another
project.

## Frontmatter

Unless asked otherwise, write the report as a `.md` file with this YAML frontmatter:

```yaml
---
title: (report's title)
created: (YYYY-MM-DD, date of creation)
updated: (YYYY-MM-DD, date of last edit)
authors: (author names; use "CLAUDE (C)" as your name; the human's entry ends in "(H)")
type: (one slug from the repo's vocabulary; omit if it has none)
---
```

Write it by hand:

- New file: write the frontmatter above, then the body.
- Existing file: add the frontmatter if missing, append `CLAUDE (C)` to `authors`
  and set `updated` to today. Keep existing keys (e.g. an old `date:`); do not
  rename them.
- Omit `type` when the repo has no `type` vocabulary.

Add no other field unless the repo asks for it (e.g. `maturity`, which is independent
of `type`, or `related`, as relative links).

## Writing practices

**Attribution.** Every H2 heading ends with an author tag: `(H)` (the human), `(C)` (Claude) or `(H+C)`.
Within a section, back-and-forth uses bold prefixes `**H:**` / `**C:**`. Never put H's
words in C's voice or vice versa; when restating a question H asked, attribute it.
Appended sections start with their date.

**Structure.** When reporting on an experiment, state the setup first, then the results (a
table if appropriate), then the main implications for the original request. Say what a
table's rows, columns and quantities are.

**Notation.** When introducing notation, say what it means, including units and
conventions (e.g. distances measured in standard deviations). Use one symbol per
quantity: not both `n` and `m` for the same sample size.

**Links.** Link other notes you reuse with a relative `.md` path. No wikilinks.

**Length.** Be brief. Keep the main text to the most important reflections and
implications; put secondary reflections and details in an appendix.

## Example

```markdown
---
title: Bandwidth sweep for the KDE baseline
created: 2026-10-01
updated: 2026-10-07
authors: Jane Doe (H), CLAUDE (C)
type: report
---

## Setup (C)

Gaussian KDE on n = 500 draws. Bandwidth h is in units of the sample standard
deviation. Rows below are bandwidths; the column is mean held-out log-likelihood.

## Results (C)

| h   | held-out log-lik |
| --- | ---------------- |
| 0.2 | -1.42            |
| 0.5 | -1.31            |

h = 0.5 is best; the baseline in [setup.md](setup.md) used 0.2.

**H:** Why not Silverman's rule?
**C:** It gives h = 0.48 here, close to the best value.

## 2026-10-07 Silverman's rule on the other datasets (H+C)

## Appendix: per-seed results (C)
```

## Final check

After writing or editing, run:

```bash
python3 ${CLAUDE_SKILL_DIR}/check_report.py PATH
```

It flags missing frontmatter keys, non-ISO dates, `updated` not today, `CLAUDE (C)`
missing from `authors`, H2 headings without an author tag, wikilinks and relative links
that do not resolve. Fix what it reports and rerun until it prints `OK`. Ignore a flag
only where the repo's conventions or the active skill say otherwise.
