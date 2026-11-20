---
name: convert-notes
description: Convert hand-written notes in a PDF into typed text (Markdown with LaTeX math). Use when the user asks to convert, transcribe, or digitize hand-written notes, or mentions "convert-notes".
---

## Input

The PDF is the one the user indicates. If only a name is given, or no folder is specified, look for it in the current directory.
If several PDFs match or none is indicated, list the candidates and ask.

Read the pages as images (`Read` with the `pages` parameter, at most 20 pages per request), since the notes are hand-written and text extraction will not work.

## Guidelines

* Convert only the requested pages. If no pages were requested, ask which ones.
* Add only the minimally required connectives (e.g. "then", "since", "where") when needed for the text to read as sentences.
* Do not elaborate on the notes' material unless requested: no added explanations, derivations, examples, or corrections of the content.

## Output

* Transcribe faithfully, keeping the order, structure (headings, lists, numbering) and notation of the notes. Write math in LaTeX (`$...$`, `$$...$$`).
* Unless told otherwise, write a `.md` file next to the PDF with the same stem and the page range in the name (e.g. `notes_p3-5.md`), and never overwrite an existing file.
* Mark anything illegible or ambiguous as `[?]`, or `[word?]` for a best guess, and list these at the end of your reply. Do not silently guess.
* Describe figures and diagrams in a one-line placeholder, e.g. `[Figure: ...]`, rather than reproducing them.
