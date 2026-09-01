# Thread / Worktree / Branch lifecycle retained in V1.3.3

Inspect the actual app-native tool definitions on every routed task. The shapes
below preserve the V1.1.1 lifecycle contract in V1.3.3 and always yield to
current schemas.

## Three different objects

Never use Thread, Worktree, and Git Branch as synonyms:

- **Thread** is the visible Codex task/conversation and its retained context.
- **Worktree** is a physical checkout directory that shares Git metadata with
  the repository. It exists to isolate file and index changes.
- **Git Branch** is a movable Git ref naming a commit history. Git permits one
  branch to be checked out in only one worktree at a time.

A Thread may run in the local checkout with no secondary worktree. A Codex
managed worktree commonly starts detached, so it may have no branch. A
permanent worktree may host several Threads. Treat all three identities and all
three lifecycle states separately.

Current official Codex documentation defines a managed worktree as temporary
and chat-associated, describes permanent worktrees as long-lived, and documents
automatic retention separately from Git branches:
<https://learn.chatgpt.com/docs/environments/git-worktrees>.

## Resolve the project

1. Read the exact saved project metadata before any create or adoption action.
2. Prefer the saved `projectId`; otherwise use a canonical Git root/cwd plus the
   stable logical project name.
3. Never match a project by title alone. Two projects can both have `前端`.

The Registry `projectKey` is `id:<projectId>` when an ID exists, otherwise a
canonical `path:<path>`, otherwise a normalized `name:<name>` for intentionally
repository-free work.

## Adoption before creation

Use Team Adoption when matching project Threads already exist:

1. Query the Registry for the exact project and normalized role.
2. Direct-read every candidate Thread ID; the real Thread API is the source of
   truth.
3. Query current project Threads, following pagination when exposed. A bounded
   recent list is not proof that an older role does not exist.
4. Match by exact project identity, role contract, cwd/worktree, and direct
   Thread content. Do not trust an unverified title alone.
5. Register the existing Thread with `Action Adopt`; record observed Worktree
   and Branch separately.
6. Mark an adopted Worktree as `management=Adopted` and
   `createdByRouter=false`. Mark its Branch ownership `PreExisting`.
7. Adoption grants scheduling/reuse authority, not deletion ownership. An
   adopted Worktree or Branch is never auto-deleted unless independent evidence
   proves the Router originally created that exact object.

Only create a missing visible role after Registry lookup, direct read, and real
project-task discovery find no accessible match. Name a newly created role
`项目名｜角色` and register its real `threadId`, never a pending client ID.

## Registry schema

The default Registry is
`$CODEX_HOME/auto-visible-team-router/thread-registry.json`. Schema 2 keeps:

- `thread`: ID, title, created/verified time, state, origin, adoption time;
- `worktree`: Thread ID, path, Branch name, Base Commit, CreatedAt, state,
  management, Router-creation proof, temporary flag, cleanup eligibility;
- `branch`: name, ownership, protected flag, merge state, cleanup eligibility;
- `delivery`: Commit/Parent SHA, QA/integration/result state, delivery state,
  compact Receipt, reconciliation result, conflict fields, and ACK time;
- optional `deliveryRecovery`: delivery health, bounded retry evidence,
  incident lineage, replacement identity, and health-check result;
- per-project Worktree Budget, default `3`.

Schema 1 is migrated in place without inventing ownership. Legacy Worktrees and
Branches become `Unknown` and are not auto-delete eligible. The Registry is an
audit index; actual Thread reads and Git commands remain the state truth.

## Reuse an existing Branch

Before creating any Branch:

1. list local branches and all worktrees without fetching or changing Git;
2. find a reasonable existing development branch for the same scope;
3. verify it is not checked out by a different active writer;
4. verify its base and commit history fit the new assignment;
5. reuse it when safe. Enabling the Router never forces a replacement branch
   hierarchy.

Do not reuse `main`, `master`, `release/*`, or another protected branch as a
parallel writer's temporary branch. Do not check out the same branch in two
worktrees.

## When a new Worktree is allowed

A new Worktree is allowed only when **two or more coding Agents truly need to
edit in parallel**, their write ownership is disjoint, and serial execution
would materially block the task. One coding Agent stays in the current safe
checkout or reuses a suitable existing Worktree.

Architect, QA, Reviewer, Research, and Security are read-only by default and do
not receive a new coding Worktree. They may inspect an existing checkout or an
exact Commit SHA. An already existing QA worktree may be adopted and reused,
but its existence is not a reason to create another.

For every Router-created temporary Worktree, record before editing:

- Thread ID;
- Branch (or explicit detached state);
- absolute Worktree Path;
- Base Commit;
- CreatedAt;
- lifecycle state.

If a named temporary Branch is required, also record Router ownership and the
protected-branch decision. A new temporary Branch is justified only when a
parallel coding writer needs a durable named ref, no reasonable existing branch
can be safely reused, and the integration owner has a clear target branch.

## Worktree Budget

Each project has a default Router-managed Worktree Budget of `3`. Count unique
retained Worktree paths whose management is `RouterCreated` or `Adopted`;
adoption therefore prevents hidden accumulation. The local primary checkout is
recorded separately and does not become a Router temporary Worktree merely
because a Thread runs there.

Before creation, also inspect the current Codex worktree setting and physical
`$CODEX_HOME/worktrees` inventory. Current official documentation says Codex
keeps the most recent 15 managed worktrees by default and that the setting is
configurable. If the configured limit is unknown or remaining capacity is one
or fewer, fail closed: do not add a worktree merely because a default number was
assumed.

At or above the project Budget, use this order:

1. reuse a compatible idle Worktree;
2. wait for the current coding task to finish;
3. run the next writer serially;
4. do not delete an unknown, adopted, or old Worktree to manufacture capacity.

## Safe Worktree retirement

The Router may retire only an exact temporary Worktree it can prove it created.
All of these gates must pass at the same time:

1. no staged, unstaged, or untracked files;
2. final Commit SHA recorded and still resolvable;
3. QA status is exactly `PASS` for that SHA;
4. the Commit is merged into the target branch, or an explicitly named durable
   ref safely retains it;
5. a fresh `git status --porcelain --untracked-files=all` is empty;
6. Worktree identity, path, Thread ID, and Registry record all agree;
7. the operation is inside the user's current authorization.

After removal, retain the audit record and set Worktree state `Removed`. Never
auto-delete a Worktree with changes, an unmerged Commit, unknown ownership, an
adopted/pre-existing origin, or an identity mismatch. Never remove an unknown
old Worktree just to get under Budget.

## Safe temporary Branch retirement

A local temporary Branch may be deleted only when all are true:

1. the Registry proves `ownership=RouterCreated`;
2. it is not `main`, `master`, `release/*`, `stable/*`, or another protected
   branch;
3. it is not checked out in any worktree;
4. its final Commit SHA is recorded and QA is `PASS`;
5. `git merge-base --is-ancestor <commit> <target>` succeeds against the exact
   target branch, proving containment;
6. the target is retained and resolvable;
7. a current authorization covers local cleanup.

User-created, pre-existing, adopted, unknown, protected, checked-out, dirty, or
unmerged Branches are never auto-deleted. Deleting a remote Branch is a push and
remains forbidden without separate explicit authorization.

## Visible delivery recovery

Every terminal specialist task first follows
[delivery-reliability.md](delivery-reliability.md): normal body or exact task
read, compact Receipt reconciliation, at most one `REDELIVER`, then Coordinator
ACK. Work completion and result delivery are separate states.

An accessible Thread that cannot produce its role return contract is
`Degraded`, not `Stale`. Before marking or replacing it, follow
[visible-thread-delivery-recovery.md](visible-thread-delivery-recovery.md). The
gate permits one controlled retry and one replacement per incident, then a
strictly bounded current-task fallback or `BLOCKED` according to risk.

## Dispatch, QA, integration, and archive

- Omit model and thinking overrides in the current V1.3.3 policy.
- Give one file/interface one writer for the run.
- Each writer returns Worktree, Branch/detached state, Commit SHA, tests, and
  status.
- Read-only roles use `ReadOnly-Guard.ps1` in an idle exact checkout. A change is
  `READ_ONLY_STATE_CHANGED` and fails closed without blaming a particular role
  until concurrent-writer attribution is proven.
- QA checks exact SHAs, never repairs developer code, and returns failures to
  the owner for a new SHA.
- Integrate only QA-approved SHAs and run post-integration regression.
- Archive a Thread only inside user authorization and update only the Thread
  state. Archiving a Thread is not the same action as deleting its Worktree or
  Branch.

## Stale recovery and caps

When a registered Thread fails direct read, mark only its Thread state `Stale`,
search real project tasks, adopt an accessible replacement when present, and
create once only when none exists. Preserve lineage. Never have two Active
entries for one exact project/role.

When direct read and identity succeed but two bounded attempts produce no body,
tools, or role conclusion, use `Degraded` recovery instead. Do not falsify the
incident as Stale merely to pass the replacement gate.

Keep no more than five active long-lived specialist Threads per project and no
more than three retained Router-managed Worktrees by default. These are
different caps. A replacement Thread does not imply a replacement Worktree or
Branch.
