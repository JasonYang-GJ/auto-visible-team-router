# V2 Thread lifecycle

## Different objects

- Thread = visible Codex task/conversation + retained working context.
- Worktree = Git checkout directory.
- Branch = Git ref.
- ProjectIdentity = authorized repository/folder identity.
- CheckoutIdentity = the real Git checkout used by one Thread.

Never use them as synonyms.

Thread cwd is not Project Identity. Before adopting a visible task, resolve its checkout with
[repository-containment.md](repository-containment.md). Different physical
paths are legal for related Worktrees; an unproved checkout is BLOCKED.

## V2 identity

Resolve `project_key` using [project-identity.md](project-identity.md). Preferred
app-native `projectId` is not required when canonical Git or path identity is
available. Supported new-batch keys are:

```text
id:<projectId>
git:<canonical-git-root>
path:<canonical-path>
```

V2 stops using `project + permanent role` as the primary Thread identity.

Use:

```text
project_key + batch_id + workstream_id
```

Capability is metadata, not identity.

## Lifecycle

```text
PROPOSED
  -> DISPATCHED
  -> RUNNING
  -> WORK_COMPLETED
  -> DELIVERY_PENDING
  -> DELIVERED
  -> ACKNOWLEDGED
  -> CLOSED
```

Failure states include:
- BLOCKED
- DEGRADED_DELIVERY
- DELIVERY_EVIDENCE_CONFLICT
- STALE_THREAD

## Creation

The current production backend does not automatically create repo-bound visible
Workstreams. `AUTO_VISIBLE_WORKTREE` is `UNSUPPORTED`.

When the user explicitly requests visible tasks, return
`READY_FOR_MANUAL_VISIBLE_DISPATCH`. The user creates the task in the Codex UI;
V2 may adopt it only after a real Thread ID, exact project/batch/workstream
identity, and Repository Containment all pass.

Do not create visible tasks:
- in SHADOW;
- for appearance;
- because a module exists;
- because a role/capability exists;
- when current task can safely own the work.

For `CURRENT_THREAD`, each serial Workstream still has its own logical identity,
Packet, owned scope, terminal checkpoint, and optional Registry record. The
same current Thread may appear in multiple Workstream records in one Batch,
provided execution is serial and ownership is never simultaneous.

## Adoption / reuse

Reuse is deliberately narrow.

A Thread may be adopted/reused only when all match:
- exact project;
- exact batch;
- exact workstream;
- same objective/ownership contract;
- direct-read verifies identity and useful current context.

Repair and delivery recovery within the same Workstream reuse the same Thread.

Cross-batch or cross-milestone reuse is not the default.

Do not search for "the project's Developer Thread" or "the project's QA Thread"
as a reusable long-lived employee.

## Thread hygiene

Prefer fresh task-scoped context for a new batch when the old Thread contains:
- prior milestone assumptions;
- unrelated implementation history;
- incompatible contracts;
- mixed project identity;
- large irrelevant test/debug narratives.

Do not replace a Thread solely to make an unmeasured Token claim.

## Registry

Default V2 registry:

```text
$CODEX_HOME/auto-visible-team-router/workstream-registry.json
```

The registry is an index, never stronger than app-native Thread/Git truth.

Recommended keys:

```yaml
project_key:
batch_id:
workstream_id:
thread:
capability:
objective:
owned_scope:
dependencies:
state:
worktree:
branch:
commit_sha:
delivery:
```

For Git-backed visible Workstreams also record nested `threadIdentity`,
`checkoutIdentity`, `worktreeIdentity`, and `branchIdentity`. Preserve the
legacy flat worktree/branch fields only as compatibility indexes; they are not
stronger than the nested evidence or live Git/App truth.

## Close

A Workstream closes only after:
- terminal result exists;
- delivery is reconciled/ACKed when a visible Thread was used;
- exact SHA/evidence is recorded when code changed;
- no unresolved ownership handoff exists.

Closing a Thread does not delete its Worktree/Branch.

## Archive/cleanup

Never auto-delete unknown/user/adopted Git objects.

Thread archive is separate from Worktree/Branch cleanup and requires current
authorization plus app-native support.

V2 prefers short lifecycle through task closure and compact checkpointing, not
aggressive deletion.
