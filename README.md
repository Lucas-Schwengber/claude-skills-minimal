# claude-skills-minimal

A small set of [Claude Code](https://code.claude.com/docs/en/skills) skills I use for
research work (writing, reviewing, and long-running experiments). This is a trimmed copy
of a personal repo, shared as is and **not actively maintained**.

## Install

```bash
git clone https://github.com/Lucas-Schwengber/claude-skills-minimal.git ~/dev/claude-skills-minimal
cd ~/dev/claude-skills-minimal
./install.sh
```

`install.sh` symlinks each skill folder into `~/.claude/skills/` (override with
`CLAUDE_SKILLS_DIR`). Re-run it after pulling. Or copy any skill folder there by hand.
Each skill is then a slash command named after its folder, e.g. `/parallel-review`.

## Skills

| Skill | What it does |
|---|---|
| `parallel-review` | Reviews a slide deck, paper draft or report with four parallel read-only reviewers (language, consistency, math and argument, literature), verifies the findings, and writes one checkbox-tracked review file. Later applies the fixes you approve. |
| `write-report` | Conventions for Markdown reports and notes: YAML frontmatter, `(H)`/`(C)` author tags (human / Claude) on sections, experiment write-up structure, notation, length. Includes `check_report.py` to lint a report. |
| `interrogate-me` | Claude interviews you about a plan or design, one decision at a time, with a recommended answer for each. |
| `parallel-work` | How to split a task across sub-agents: when to delegate, how to brief them, how to check what they return. |
| `supervised-implement` | Implement a plan together, one reviewed edit at a time, with proposals shown in chat before they reach a file. |
| `docstring` | NumPy-style Python docstrings and section-divider comments. |
| `convert-notes` | Transcribes handwritten notes in a PDF to Markdown with LaTeX math. |
| `resume-later` | Wraps up a session before you leave: finds work that would die with it, relaunches or records it, and writes a handoff note with ready-made checks. |
| `clean-sessions` | Finds dangling Claude Code processes (stuck, orphaned, long idle) and asks which to end. |
| `resources-summary` | One table of the jobs and processes behind a session: node, cores, memory, GPUs, elapsed, predicted finish. |

## Notes

- `resume-later` and `resources-summary` assume a **Slurm** cluster and a Linux login
  machine. `clean-sessions` is Linux-only.
- `interrogate-me` is a lightly adapted version of an idea from
  [mattpocock/skills](https://github.com/mattpocock/skills).
- Skills can run shell commands and pre-approve tools. Read a skill before installing it.
- Skills are plain Markdown. Edit them freely to match your own conventions.
