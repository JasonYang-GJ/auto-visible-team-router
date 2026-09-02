# Repository / Worktree containment contract

Project identity and checkout placement are different facts. A visible Thread
may run in the primary checkout or in a related Git Worktree at another
physical path. Never compare `Thread cwd == CanonicalGitRoot` as the whole
containment decision.

## Public resolver

Run `scripts/Resolve-RepositoryContainment.ps1` for every manually created
visible Coordinator or Workstream before adopting it or allowing it to
read/write the Batch repo.
Record:

```text
ThreadId
ThreadCwd
ThreadGitRoot
ThreadGitDir
ThreadGitCommonDir
CanonicalGitRoot
CanonicalGitCommonDir
WorktreeInventoryMatch
StartingSHA
CheckoutType
ContainmentStatus
```

The JSON result also records the canonical `ProjectKey`, branch/detached state,
dirty attribution, management class, lineage result, optional app-native
evidence match, and whether Router creation is actually proven.

## Containment categories

### PRIMARY_CHECKOUT

`canonical(ThreadGitRoot) == canonical(AuthorizedGitRoot)`, both resolve to the
same `git-common-dir`, the checkout is in the canonical inventory, lineage is
explained, and no dirty state is unattributed.

### RELATED_GIT_WORKTREE

Physical paths differ, but all of these are true:

1. Thread cwd is a valid Git checkout;
2. Thread and canonical checkout share the same canonicalized
   `git-common-dir`;
3. canonical `git worktree list --porcelain` identifies the Thread checkout,
   or exact app-native evidence binds that Thread/checkout to the authorized
   repository;
4. starting SHA equals the Batch baseline or supplied lineage evidence matches
   both SHAs and Git ancestry;
5. every dirty path is explicitly attributed.

A detached HEAD is allowed when these checks pass.

### UNRELATED_CHECKOUT

Both paths are valid Git checkouts but their canonical `git-common-dir` values
differ. Similar directory names, a `-2` suffix, equal HEAD, equal files, equal
remote URL, or equal Thread title never override this result. Independent
clones are blocked by default.

### UNKNOWN

Git identity, common-dir, inventory/app evidence, or checkout state cannot be
proved. Return `CONTAINMENT_UNPROVEN` and do not dispatch writers.

## Checkout and ownership identity

Registry records separate objects:

```yaml
ProjectIdentity:
ThreadIdentity:
CheckoutIdentity:
WorktreeIdentity:
BranchIdentity:
```

Checkout types are `PRIMARY_CHECKOUT`, `CODEX_MANAGED_WORKTREE`,
`PERMANENT_WORKTREE`, `UNRELATED_CHECKOUT`, or `UNKNOWN`.

`management=CODEX_MANAGED` describes lifecycle authority. It does not imply
`createdByRouter=true`. Router creation may be recorded only when exact
app-native request/thread/checkout evidence matches. Router never deletes
Codex-managed, external, unknown, or merely adopted Worktrees.

The current `AUTO_VISIBLE_WORKTREE` backend is unsupported because the tool
surface cannot reliably return and reconcile that complete binding. A related
Git Worktree without a real app-native Thread binding remains unowned evidence,
not an executable Workstream.

## Historical isolation

A new resolver contract does not retroactively adopt old Worktrees. In
particular, the historical late detached Worktree from a failed Canary remains
`UNKNOWN_NON_OWNED` unless a separately authorized, fresh evidence process
proves otherwise. It cannot become evidence for a new Batch and cannot be
deleted to manufacture capacity.
