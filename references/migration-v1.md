# V1.3.3 -> V2 in-place migration

## Goal

Replace the installed/repository V1.3.3 routing model with V2 while preserving a
clean rollback baseline in Git/GitHub and preventing old role-thread state from
being misread as V2 workstream state.

## Preflight

Before editing:

1. resolve the exact `auto-visible-team-router` repository and canonical root;
2. require a clean working tree;
3. record current branch, exact HEAD SHA, origin URL, installed Skill path,
   current V1 VERSION, V1 registry paths/hashes, and current global AGENTS block;
4. confirm the remote contains the V1.3.3 rollback baseline;
5. create upgrade branch `codex/v2-workstream-router`.

Do not edit `main` directly.

## State backup

Before changing installed V1 runtime state, copy the current
`$CODEX_HOME/auto-visible-team-router/` state into a timestamped backup, at
minimum preserving any thread registry, module registry, state/config metadata,
installed V1 Skill files, and managed AGENTS block/hash.

Do not delete this rollback backup after V2 passes.

## Repository replacement

Keep the canonical repository/Skill identity:

```text
name: auto-visible-team-router
VERSION: 2.0.0
```

Retire/rewrite semantics that conflict with V2:
- numeric Complexity Score -> team size;
- permanent role Thread adoption/reuse;
- `project + role` Thread identity;
- multi-file/cross-layer automatic QA preference;
- role catalog as a Thread-creation driver;
- long-lived Developer/QA/Architect/Security as the normal team model.

Retain/refactor:
- exact baseline/SHA;
- one writer per scope;
- bounded context packet;
- Read Scope Ladder;
- Context Delta;
- Existing Capability Check;
- Worktree Budget 3;
- read-only guard;
- high-risk independent QA/Security;
- compact delivery reconciliation;
- non-destructive Git cleanup.

## Registry migration

Do not convert V1 permanent-role Thread entries into V2 workstreams.

V2 identity is:

```text
project_key + batch_id + workstream_id
```

For new V2 batches, resolve `project_key` by app-native Project ID, then
canonical Git root, then canonical path. `projectId` is not mandatory and old
V1 role/title identity is never a fallback.

Archive V1 state, then initialize a fresh V2 Workstream Registry.

Old visible role Threads may remain visible in Codex history, but V2 must not
adopt them merely because they are named Developer/QA/Architect/Security.

Repository containment migration is prospective. Add separate Project,
Thread, Checkout, Worktree, and Branch identities for new V2 Workstreams; do
not retroactively assign historical unknown Worktrees merely because a new
resolver can inspect them. In particular, late detached Canary artifacts remain
unknown/non-owned unless a fresh, separately authorized ownership proof exists.

## AGENTS migration

Replace the managed V1 routing block with one compact V2 block. Do not append V2
below V1.

After replacement:
- exactly one managed router block exists;
- it names the V2 workstream policy;
- start a fresh Codex task/session before relying on V2 behavior because old
  tasks may retain the previous instruction chain.

## Promotion sequence

```text
V1 Git baseline
  -> upgrade branch
  -> V2 repository rewrite
  -> offline tests
  -> install V2 SHADOW
  -> platform-adapted synthetic Canary
  -> V2 ACTIVE
  -> fresh task/session
  -> one bounded real-project Canary
  -> final regression
  -> commit/push upgrade branch
  -> merge/fast-forward main only after PASS
```

## Rollback

On a material failure:
1. stop/disable V2 routing;
2. restore repository/install from recorded V1 Git SHA;
3. restore archived V1 runtime/registry and managed AGENTS block;
4. start a fresh Codex task/session;
5. verify V1 status and Git cleanliness.

Never invent a partial hybrid V1/V2 rollback.

## Exact V2 Release Candidate update

After V2 is already installed, do not reuse `InstallShadow` and do not install
from a dirty checkout. Freeze and commit one Release Candidate, run
`tests/Run-ReleaseCandidateGate.ps1` against its exact SHA, export that commit
without Git metadata, then use `Manage-Global.ps1 -Action UpdateV2Shadow` with
the same SHA as `SourceIdentity`.

The update backs up the current installed V2 and Registry, preserves the
original V1 rollback backup/legacy archive, installs only allowlisted package
files, initializes a fresh V2 Workstream Registry, and returns to SHADOW.
Compare source/export and installed file manifests before ACTIVE promotion.
