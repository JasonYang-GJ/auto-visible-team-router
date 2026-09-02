# Runtime modes and single-router guarantee

## SHADOW

Used during upgrade validation. No visible specialist dispatch, product writes,
Worktree creation, or integration. It may only propose V2 routes and run
bounded/offline validation.

## CANARY

Bounded real V2 execution for an exact project/batch after old V1 routing has
been disabled for that task/session.

## ACTIVE

Production V2 routing after upgrade gates pass.

## Single-router rule

After V2 replacement there must be exactly one active routing policy.

If a V1 managed AGENTS block remains, V1 skill code can still auto-route, an old
session retains V1 routing instructions, or V1/V2 dispatch are both possible,
fail closed:

```text
DUAL_ROUTER_BLOCKED
```

Do not dispatch until the conflict is removed.

## Fresh-session requirement

After replacing global routing instructions or the installed Skill, start a
fresh task/session before the V2 real Canary.

## Missing/ambiguous state

During upgrade, fail closed to SHADOW/BLOCKED. After verified promotion, runtime
should be ACTIVE; inconsistent state must not silently reconstruct V1 behavior.
