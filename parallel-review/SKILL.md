---
name: parallel-review
description: Review a written artifact (slide deck, paper draft, report, poster) with four parallel read-only reviewers (language and typography, internal consistency, mathematics and argument, literature), verify their findings, and write one itemized, checkbox-tracked review file next to the document; later apply the approved fixes. Use when the user asks to go through, proofread, review or audit slides or a draft for typos, grammar, inconsistencies, conceptual or mathematical errors, logical gaps, or wrong or missing citations, wants a list of issues by type, asks to apply the `[C]` items of a review file, asks to make slide transitions gradual, or mentions "parallel review".
---

Review a document with four parallel reviewers, check what they report, and leave one review file next to the document. Slides are the main case; the same steps work for a paper draft, report or poster. Briefing and sizing of sub-agents follow the parallel-work skill: read it first, it is not repeated here.

Steps 1 to 4 are the review. Step 5 (prefilled boxes) and step 6 (applying fixes) happen only when the user asks. Step 7 applies to slide decks.

## 1. Setup

- Read the target file(s) fully yourself. You cannot judge the reports otherwise.
- Record the snapshot that line numbers will refer to: `date '+%F %H:%M'; wc -l FILE; sha256sum FILE`. If you read the file earlier in the session, compare first: another session may be editing it.
- List what sits next to the document: figures, data files, plotting scripts, build log, rendered PDF, bibliography, reviewer notes. Reviewers get these paths.
- Check whether the document is tracked in git (`git status --short DIR`). It matters in step 6.

## 2. Fan out four reviewers

Launch all four in one message, each briefed as in parallel-work (objective, scope, context, output, permissions). Common to every brief:

- Read-only on the project. The only file a reviewer writes is its full report, at a scratchpad path you give it. It returns that path plus a summary of at most 150 words.
- Every item carries: line number, the quoted text, why it is a problem, a proposed fix, and a certainty tag (certain, likely, unsure).
- Ignore commented-out content.
- The file is the truth. If the brief and the file disagree (a name, a parameter, a number), trust the file and say so.
- Stay in your lens; out-of-lens finds get one line each at the end.

The lenses:

1. **Language and typography** (a cheaper model is fine). Spelling, grammar, non-idiomatic phrasing, punctuation and capitalization consistency, citation formatting. Layout problems read from the build log and the rendered output: overfull boxes, lines that overrun by one or two words, repeated frame titles.
2. **Internal consistency.** Notation (one object written two ways, one symbol with two meanings, used before defined); terminology drift; numbers that disagree between slides, or between a slide and its table, figure, CSV or script; structure (cross-references, outline vs actual order); figures vs the text that describes them. Recompute table entries from the data files when they exist.
3. **Mathematics and argument.** Act as a skeptical committee member or referee. First check every formula and claim (signs, constants, hypotheses, scalar vs matrix, first-order approximations, bias and rate claims) by doing the short computation, not by asserting. Then logical gaps: unjustified steps, conclusions the evidence does not support, hidden assumptions, overclaims, motivation the results do not deliver. Tag each item as error, imprecise, or likely question.
4. **Literature.** Verify every citation with web search: authors, year, venue, and that the work contains what is attributed to it. Look for close prior work near anything labeled "ours" or "new". List topics used without a citation. Tag each item as verified online, from memory, or unverified, and give the source. May query the user's Zotero read-only (zotero-cli skill, if installed). Never put the author's name, the project name or identifying text from the document into a web query.

## 3. Verify before passing on

While they run, do not redo their work. When they return, read each report in full, then check the claims that matter yourself:

- recompute numbers from the data files; re-derive the formulas said to be wrong;
- open the cited line and confirm the quote is there and live (not in a comment);
- check layout claims in the rendered output (`pdftotext -layout main.pdf -`) and the build log.

Drop what does not hold and downgrade what is weaker than claimed. Then re-run the snapshot check from step 1. If the source changed, re-anchor every item to the current line numbers (search for the quoted text) and drop items already fixed.

## 4. Write the review file

One markdown file next to the document (for example `slide_review.md`). It is a synthesis, not the four reports pasted together: deduplicate across reviewers and group by type of issue, not by reviewer.

Groups, in this order (omit empty ones): 1 spelling, grammar and typography; 2 inconsistencies; 3 conceptual and mathematical errors; 4 logical gaps in the arguments; 5 literature; 6 speaker notes and source comments (only what is still worth flagging there, such as a note that contradicts the slide).

````markdown
# Review of main.tex

Snapshot: `main.tex` on 2026-11-15 14:32, 1840 lines. Line numbers refer to it.
Marks: `[ ]` open, `[x]` addressed, `[C]` apply Claude's proposed fix, `[H]` the human will check it.
Trust: (src) read off the source. (calc) recomputed or re-derived by the orchestrator.
(web) literature checked online by a reviewer. (mem) literature from memory, not verified.
Not verified: <what nobody checked, e.g. figures not regenerated, a paper behind a paywall>.

## Start here
- 3.2, 2.5, 5.1: one line each on why these cost the most if left.

## 1. Spelling, grammar, typography
- [ ] **1.1** *Frame title* (l. 412) "quoted text": the issue in one sentence. **Fix:** the exact replacement. (src)
````

- IDs are stable (1.1, 2.3, ...). Never renumber after the file is shared; new items take the next free number.
- One list entry per item: checkbox, ID, frame or section title, line number, quoted text, the issue, then `**Fix:**` with a concrete change that could be applied as written.
- Every item ends with its trust marker. Be honest about what was and was not verified. A literature item nobody checked online stays (mem) and never gets a confident wording.

## 5. Prefilling the boxes (only if asked)

- `[C]`: the fix is mechanical, or was recomputed or re-derived. Typos, grammar, overruns, numbers taken from the data, contained notation fixes, citation facts known independently.
- `[H]`: anything that changes a claim or headline, renames a symbol across the whole document, regenerates a figure, changes structure or titles, touches wording the user dictated, or rests on unverified literature.
- Tell the user which `[C]` items change a statement rather than fix a slip.

## 6. Applying `[C]` items (only when the user says so)

1. Re-read the review file: the user may have flipped boxes. Apply only what is marked `[C]` now.
2. Re-check the source against the snapshot. If it changed, re-anchor first.
3. If the source is not under version control, copy it to the scratchpad and tell the user the backup's full path.
4. Apply each fix as an exact-string replacement that asserts the expected number of matches (the Edit tool, or a script with `assert text.count(old) == n`). Never edit by line number.
5. Rebuild with the project's own build command.
6. Compare the log and rendered output with the state before: new overfull boxes, orphan words, lines that now wrap, page-count changes (`pdfinfo`). Fix what the edits caused.
7. Mark the applied items `[x]` in the review file. Report anything that could not be applied and why.

## 7. Slide decks: gradual reveals

For a slide deck there is one more task: make the content of each slide appear step by step. In beamer: `\pause`, `\onslide`, `\uncover`, `\only`, `[<+->]` on lists.

- Derivations are revealed one step at a time: one equality, or one line of an `align`, per step. Inside `align` use `\uncover<n->{...}` or `\onslide<n->`; `\pause` is unreliable in amsmath environments.
- Multi-part diagrams appear part by part (`\visible<n->` in TikZ, `\includegraphics<n>` or `\only<n>` for image sequences).
- Prefer `\uncover`, `\onslide` and `\visible`, which reserve space, over `\only`, which makes content jump. Give swapped figures a fixed bounding box (`overlayarea`, `overprint`, or a fixed-size TikZ bounding box).
- After building, page through the overlays to confirm nothing jumps, and check that the footer still counts frames, not PDF pages.

This is a writer task, unlike the reviewers. It edits the source, so confirm with the user first if they asked only for a review, and back up as in step 6. Run it as its own agent or step, never concurrently with another writer on the same file. Either finish it before the reviewers start, or re-anchor all line numbers afterward.

## Pitfalls (all happened)

- **The source moved mid-review.** Another session edited the file, so line numbers drifted. Hence the snapshot in the header and the re-check before steps 4 and 6.
- **Stale brief.** Reviewers were given an outdated parameter name and reported against it. Hence "the file is the truth" in every brief.
- **Untracked directory.** The document was not in git, so nothing could undo a bulk edit. Hence the backup in step 6.
- **Confident unverified literature.** Findings from memory came back in the same register as findings checked online. Keep the (web) and (mem) markers all the way into the final file.
