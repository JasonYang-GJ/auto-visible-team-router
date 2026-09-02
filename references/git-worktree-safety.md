# Git / Worktree safety

## Core rules

1. One active writer per owned file/scope.
2. Parallel coding requires disjoint write ownership.
3. Unclear overlap -> SERIALIZE.
4. One coding lane normally uses the current safe checkout or a suitable
   existing worktree.
5. New Worktrees exist to isolate genuine parallel writers, not to create
   visual team structure. The current Router cannot create them automatically.
6. Default V2 Router-managed Worktree Budget = 3.
7. Read-only gates do not get new coding Worktrees by default.
8. Never delete unknown/adopted/user objects to create capacity.

## Before coding

Capture:
- repo root;
- baseline SHA;
- current Branch/detached state;
- worktree path;
- `git status --porcelain --untracked-files=all`;
- relevant existing worktrees/branches when parallelism is planned.

Run [repository-containment.md](repository-containment.md) for every new
visible writer checkout. Path inequality is not failure, and path similarity is
not proof. Require common-dir plus canonical inventory or equivalent app-native
evidence before treating it as related.

If the checkout has unrelated dirty state and safe attribution/containment
cannot be established, fail closed or use a separately authorized clean
worktree. Do not reset/clean unknown changes.

## Parallel worktree gate

Adopt user-created separate coding Worktrees only when:
- at least 2 coding lanes are truly parallel;
- owned scopes are disjoint;
- branches/worktrees cannot collide;
- dependency contracts are frozen;
- parallel benefit is material.

`AUTO_VISIBLE_WORKTREE` is disabled by the platform capability matrix. Never
replace missing app-native Thread/checkout lineage with manual `git worktree
add`, a directory copy, a guessed client ID, or historical object adoption.

At Budget:
1. reuse compatible idle worktree;
2. wait;
3. serialize;
4. never delete unknown objects to manufacture capacity.

## Branch safety

Do not:
- check the same Branch out in two Worktrees;
- use protected branches as temporary parallel writer branches;
- delete unmerged/unknown/user/adopted branches;
- push without explicit authorization.

## Read-only gate

Architect/QA/Security/Reviewer/Research should inspect exact evidence without
modifying product code.

Use `scripts/ReadOnly-Guard.ps1` before/after when a real checkout is used.

A guard difference means `READ_ONLY_STATE_CHANGED`; it does not by itself prove
which actor caused the change.

## Integration

Integrate only exact, resolvable writer SHAs with known lineage.

Before combine:
- verify each Workstream SHA;
- verify ownership;
- compare shared contracts;
- fail on unexpected overlap.

After combine:
- targeted integration tests;
- risk-based QA/Security;
- proportionate regression.

## Cleanup

This V2 package does not authorize destructive Git cleanup.

Any cleanup implementation in a real environment must prove:
- clean state;
- retained exact commit;
- integration/containment;
- Router ownership;
- current user authorization.

Codex-managed lifecycle and Router ownership are separate. A Worktree may be
`CODEX_MANAGED` while `createdByRouter=false`. Never delete Codex-managed,
unknown, external, or historical late Worktrees merely because they are empty
or consume apparent capacity.
