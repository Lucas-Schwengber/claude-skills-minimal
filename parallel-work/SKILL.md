---
name: parallel-work
description: Use when a task splits into 2+ independent subtasks (no shared state, no ordering dependency), or when a broad search/read would flood the main context. Not for small or tightly coupled work.
---

# Parallel work

Goal: keep the main context small by delegating self-contained subtasks to sub-agents and receiving only their conclusions.

## When
- Delegate: independent subtasks, broad searches across many files or sources, research split by topic.
- Don't: tasks that need each other's output, edits to the same files, anything under ~3 tool calls.

## Briefing each sub-agent (they see nothing of this conversation)
1. Objective: one sentence saying what "done" is.
2. Scope: files, directories or sources in bounds; what NOT to touch.
3. Context: key facts, decisions already made, relevant paths.
4. Output: exact format and a word limit; long outputs go to a file, and the agent returns the path plus a summary.
5. Permissions: read-only or may-edit. Writers never share files (use worktree isolation for code).

## Sizing
- 1 agent for a focused lookup; 2-4 for comparisons or multi-part tasks; more only on request.
- Use a cheaper model for pure search and reading.

## After they return
- Read each report; check for contradictions and overlapping edits.
- Verify the claims that matter (run tests, open the cited file and line) before reporting them.
- Synthesize; don't paste reports through to the user.
