# Migration, mode change, and integration safety

Read this reference only for Router upgrades/adoption, Shadow/Active changes,
integration ownership, or an in-flight handoff. It is not part of the Level 0
fast path.

## Contents

- [Preserve in-flight work](#preserve-in-flight-work)
- [Safe checkpoints](#safe-checkpoints)
- [Project mode authorization](#project-mode-authorization)
- [Integration ownership](#integration-ownership)
- [Packet invalidation](#packet-invalidation)
- [Read-only attribution](#read-only-attribution)
- [Upgrade sequence](#upgrade-sequence)

## Preserve in-flight work

Installing or adopting a newer Router policy must not interrupt a current
Developer/QA cycle. Do not automatically reroute the assignment, replace its
visible task, move its checkout, change its Branch, overwrite its Packet, or
force the project into a new governance mode.

Continue the existing batch to a safe checkpoint, preserve the exact Thread,
Worktree, Branch, Packet, and evidence, then adopt them into the new policy.
Only an actual writer collision, permission/security breach, destructive-risk
condition, or verified Git corruption justifies immediate interruption.

## Safe checkpoints

A safe checkpoint records enough state to resume or recover without guessing:

- exact Thread ID and role;
- Worktree path and fresh `git status`, including untracked files;
- Branch or detached state, base SHA, current HEAD, and candidate commit;
- Packet ID/version and current allowed write scope;
- QA state and exact SHA last checked;
- uncommitted-work disposition and a durable recovery point.

Uncommitted or unknown work is not a checkpoint. Do not change mode, release a
lease, or move ownership until the work is committed, deliberately retained in
the same checkout, or explicitly handed back to the user.

## Project mode authorization

Shadow remains the default and does not persist module proposals. Enabling
Active requires recorded `AuthorizedAt`, `AuthorizationEvidence`, the exact
`AuthorizedProjectKey`, previous/new mode, and either a verified baseline commit
or architecture-map evidence. Running `SetProjectMode` is not itself proof of
authorization, and a similarly named project never inherits authorization.

An Active-to-Shadow transition is blocked while any Active lease remains.
Release it at a safe checkpoint, verify and mark it stale, or perform a recorded
safe migration first. Mode changes do not rewrite current Packets.

## Integration ownership

The current Coordinator is the default Integration Owner. A Developer returns
candidate commits; QA verifies exact SHAs; Architect returns decisions and
consistency evidence. None becomes integration owner merely by producing a
commit or PASS result.

An alternate Integration Owner is valid only when the record names:

- owner role and real Thread ID;
- exact target Branch and integration scope;
- reason and authorization evidence;
- accepted candidate SHAs and required QA/architecture gates.

Integration combines only approved candidate SHAs, then runs post-integration
regression. It does not grant Push, release, deploy, or cleanup permission.

## Packet invalidation

Issue a new Packet version before continuing when any of these changes:

- baseline or integration baseline;
- Branch, Worktree, project stage, or Integration Owner;
- module owner, responsibility boundary, interface contract, or allowed paths;
- permission, data ownership, security boundary, or capability evidence that
  contradicts the current plan.

A QA repair with unchanged scope, contract, acceptance, and ownership uses a
Context Delta with old/new SHA. A boundary or authorization change increments
the Packet version; it is not disguised as a repair delta.

## Read-only attribution

Run the ReadOnly Guard only against the same idle checkout and exact baseline
SHA, with coding writers quiescent for the guard window. `READ_ONLY_CONFIRMED`
means no repository-state change was observed. `READ_ONLY_STATE_CHANGED` fails
closed and requires investigation; it does not attribute the change to QA,
Architect, Reviewer, Research, or Security when another process could have
written concurrently.

## Upgrade sequence

1. Inventory current in-flight Developer/QA work without changing it.
2. Let each batch reach a safe checkpoint and capture its evidence.
3. Preserve and adopt compatible Thread, Worktree, Branch, Packet, and lease
   identity; do not recreate them for the new version.
4. Keep the project in Shadow unless exact Active authorization is present.
5. Observe two or three new tasks before proposing project-specific Active
   governance; this is an observation guideline, not automatic permission.
6. Report automated evidence separately from real Codex App evidence.
