---
name: digest-make
description: Create a copy of an LLM written report with the sections content blanked to be filled out by a user with comments and questions. Use when user asks or mentions "make a digest file".
---

Create a copy of an .md report or literature review file in the following manner:
- Save it as `<original_name>_digest.md` in a `_digests/` folder inside the original's directory (create the folder if missing), unless otherwise specified. This keeps digests out of the main file listing.
- On metadata (see the `write-report` skill): append "digest" to the title; set `created` and `updated` to today (if the file uses a single `date:` key, set that instead); set `type: digest` (or the repo's closest equivalent, or omit it if the repo has no `type` vocabulary), `maturity: raw` if the file has that key, and `authors` to the human only; add the original to `related` as a relative link (`../<original_name>.md`, since the digest sits one folder down). Otherwise keep the metadata the same.
- Keep the section and sub-section structure but make the contents blank. Retag each heading's author tag as (H), since the digest is the human's to fill in.
- Add a last section called "Other comments/reflections (H)".
- Any other relative links kept in the digest must resolve from inside `_digests/` (prefix them with `../`).

Never overwrite an existing digest, which may hold the user's notes; ask before replacing one. If a different location is specified, move the file there and fix the `../` prefixes to match.

After creating the digest, expect follow-up questions about the original document. Read it in full, along with the notes in its `related` field and any files, code or sources it relies on that you would need to answer questions about it.
