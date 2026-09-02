# Execution backend policy

Logical routing and execution placement are separate decisions.

Logical routes remain:

```text
LOCAL | SERIAL_1 | PARALLEL_2 | PARALLEL_3 | PLAN_FIRST | BLOCKED
```

Execution backends are:

```text
CURRENT_THREAD
COLLAB_SUBAGENT
MANUAL_VISIBLE_WORKTREE
AUTO_VISIBLE_WORKTREE
```

A logical `PARALLEL_2` or `PARALLEL_3` result describes independent bounded
deliverables. It does not promise that the current platform can run those
deliverables concurrently.

## Platform capability matrix

| Backend | Availability | Sidebar visible | Independent context | Explicit cwd | Independent checkout | Coding parallelism |
| --- | --- | --- | --- | --- | --- | --- |
| `CURRENT_THREAD` | AVAILABLE | current task | current context | current checkout | no | serial only |
| `COLLAB_SUBAGENT` | AVAILABLE_WITH_LIMITS | no | yes | no | no; agents share the same working tree | FORBIDDEN |
| `MANUAL_VISIBLE_WORKTREE` | OPTIONAL_USER_ASSISTED | yes after user creation | yes | app-selected | must pass containment | only after verified adoption |
| `AUTO_VISIBLE_WORKTREE` | UNSUPPORTED | unproven | unproven | unproven | binding unproven | FORBIDDEN |

The collaboration capability assessment above comes from the current tool
schema. It exposes stable Agent identity, result delivery, bounded packets, and
independent model context, but no cwd or Worktree parameter. All collaboration
Agents share the same filesystem and working directory. Therefore it may be
used for Research, Reviewer, or bounded read-only analysis when independently
valuable, but not for parallel coding.

## Selection order

1. `CURRENT_THREAD` when one owner can safely complete the work.
2. `COLLAB_SUBAGENT` only when the requested capability exists and has distinct
   value. Coding requires proven independent safe checkout support.
3. `MANUAL_VISIBLE_WORKTREE` only when the user explicitly asks for multiple
   visible Codex tasks.
4. `AUTO_VISIBLE_WORKTREE` is disabled by the current capability matrix.

The production Router must not call app-native automatic Thread creation for a
repo-bound coding Workstream while `AUTO_VISIBLE_WORKTREE` is `UNSUPPORTED`.

## Serialized fallback

When the logical route is parallel but no safe parallel backend exists:

```text
Workstream A -> compact checkpoint -> Workstream B -> Integration
```

For three or more deliverables, execute serialized waves while preserving the
planned dependency order. Use one Workstream Packet, bounded ownership scope,
and compact checkpoint per Workstream. Never mix simultaneous write ownership
inside one step.

Backend unavailability does not block an ordinary Feature. Return
`SERIALIZED_FALLBACK` or `SERIALIZED_WAVES`. Return `BLOCKED` only when the
correctness objective itself requires true parallel execution, such as a
specific race or concurrency reproduction.

## Manual visible adoption

When the user explicitly requests visible parallel work:

1. freeze Workstream A/B packets and ownership;
2. return `READY_FOR_MANUAL_VISIBLE_DISPATCH`;
3. the user creates Worktree tasks from the correct Project in the Codex UI;
4. obtain the real Thread ID;
5. run Repository Containment against the real checkout;
6. adopt only after exact project, batch, workstream, Thread, and containment
   evidence all pass.

The Router does not create or infer the visible task. A `clientThreadId`, path
name, matching HEAD, or historical Worktree is not adoption evidence.
