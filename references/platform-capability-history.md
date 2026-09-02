# Platform capability history

This file preserves capability evidence. It is diagnostic history, not a pool
of reusable Threads, Worktrees, Receipts, or PASS results.

## r1

Projectless/fork-based visible-task attempts did not establish a verifiable
project-scoped Thread-to-Worktree binding. No blocked checkout was adopted.

## r2

`directoryName`-only creation produced a same-name sibling directory that did
not prove Git repository containment. The Batch stopped before workload C-G.

## r3

The repository-containment contract correctly rejected a non-Git sibling
checkout. Similar names and historical state were not accepted as identity.

## r4

Project-scoped `create_thread` with a Worktree environment returned only a
temporary `clientThreadId`. Bounded waits did not produce a real Thread ID that
could be reconciled to the request and checkout. Git showed a related, clean,
detached Codex-managed Worktree at the Batch baseline, but the checkout already
existed in inventory and app-native creation lineage was not proven.

Result:

```text
PROJECT_SCOPED_WORKTREE_BINDING_FAILED
AUTO_VISIBLE_WORKTREE = UNSUPPORTED_BY_CURRENT_TOOL_SURFACE
reason = THREAD_CREATION_PLATFORM_LIMITATION
```

This is a platform capability limit, not a failure of logical Workstream
routing. Do not run r5/r6 automatic visible-binding experiments until an
app-native tool returns a verifiable real Thread ID, project binding, checkout
binding, and creation lineage.

Historical unknown or unowned Worktrees remain preserved. They are never
deleted, renamed, reused, or retroactively claimed to manufacture capacity.
