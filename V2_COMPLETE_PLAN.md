# Complete V2 in-place upgrade plan

## Target

Upgrade `auto-visible-team-router` V1.3.3 -> V2.0.0 in place.

## Architecture

```text
User requirement
      ↓
Batch Coordinator
      ↓
Project Identity (id / git / path)
      ↓
Deliverable decomposition
      ↓
Dependency DAG
      ↓
Single-owner test
      ↓
Parallel Benefit Gate
      ├─ LOCAL
      ├─ SERIAL_1
      ├─ PARALLEL_2
      ├─ PARALLEL_3
      └─ PLAN_FIRST
      ↓
Execution Backend Selection
      ├─ CURRENT_THREAD (default)
      ├─ COLLAB_SUBAGENT (read-only unless isolated checkout is proven)
      ├─ MANUAL_VISIBLE_WORKTREE (user assisted)
      └─ AUTO_VISIBLE_WORKTREE (UNSUPPORTED)
      ↓
Serialized fallback when logical parallelism has no safe backend
      ↓
Workstream execution
      ↓
Integration (only if needed)
      ↓
Risk-based gates
      ├─ Architect if real architecture/contract decision
      ├─ QA if high-risk or multi-lane integration
      ├─ Security if trust/secret/auth boundary changes
      └─ Reviewer if ambiguous/repeated failure
      ↓
Compact delivery / exact evidence
```

## What V2 removes

- permanent project-role Thread model;
- Complexity Score -> Agent count;
- role-first routing;
- automatic long-lived Developer reuse;
- multi-file/cross-layer automatic QA preference;
- permanent Architect/QA/Security staff concept;
- context accumulation across unrelated milestones.

## What V2 keeps

- exact SHA;
- one writer per scope;
- bounded context;
- Read Scope Ladder;
- Context Delta;
- Existing Capability Check;
- Worktree isolation;
- Worktree Budget 3;
- read-only verification;
- high-risk QA/Security;
- compact delivery reconciliation;
- fail-closed Git safety.
- separate Project, Thread, Checkout, Worktree, and Branch identities.
- Codex-managed Worktree adoption without claiming Router ownership.
- logical route / execution backend separation.
- platform capability matrix and serialized degradation.

## Thread lifecycle

`project + batch + workstream`

New batch -> fresh workstream context by default.
Same workstream repair -> reuse thread + Context Delta.

## Default Agent policy

```text
CURRENT_THREAD is the default
COLLAB_SUBAGENT coding is forbidden while Agents share one checkout
MANUAL_VISIBLE_WORKTREE only after an explicit user request and verified adoption
AUTO_VISIBLE_WORKTREE is UNSUPPORTED by the current tool surface
Logical PARALLEL_2/PARALLEL_3 uses serialized fallback when isolation is unavailable
```

## Upgrade mechanics

1. Record exact V1 Git/GitHub baseline.
2. Create upgrade branch.
3. Rewrite router source to V2.
4. Offline tests.
5. Backup installed V1 runtime.
6. Install V2 SHADOW in place.
7. Platform-adapted synthetic Canary without AUTO_VISIBLE_WORKTREE.
8. Promote V2 ACTIVE.
9. Fresh Codex session.
10. Bounded real Canary.
11. Final regression.
12. Commit/push branch.
13. Merge main only after PASS.
14. Keep V1 rollback evidence.

## Token claim

V2 is intentionally designed to reduce redundant model contexts and repeated
role-based reading, but no percentage is accepted until Codex exposes measured
usage from comparable runs.
