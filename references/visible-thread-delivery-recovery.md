# Visible Thread delivery recovery

Read this reference only after the V1.3.3
[delivery reconciliation](delivery-reliability.md) path and its one
`REDELIVER` attempt fail to recover an accessible specialist's role result.
`completed` is a task transport state, not proof that the role delivered a
usable result.

## Contents

- [State semantics](#state-semantics)
- [Output Delivery Failure Gate](#output-delivery-failure-gate)
- [Verified replacement](#verified-replacement)
- [Replacement health check](#replacement-health-check)
- [Current-task safe fallback](#current-task-safe-fallback)
- [Evidence reuse](#evidence-reuse)
- [Final reporting](#final-reporting)

## State semantics

- `Active`: accessible and currently eligible for verified assignment/reuse.
- `Stale`: identity, accessibility, project binding, or current state cannot be
  reliably confirmed.
- `Degraded`: direct read and identity are confirmed, but bounded evidence proves
  the task cannot reliably deliver its role return contract.
- `Archived`: intentionally inactive; it is not a delivery-success claim.

Never relabel a delivery failure as Stale. Keep Thread Registry schema 2 and add
only optional `deliveryRecovery` fields. Registry evidence remains an index;
real Thread reads, output records, Git, and ReadOnly Guard are truth sources.

## Output Delivery Failure Gate

Mark `THREAD_DELIVERY_DEGRADED` only when all conditions are met:

1. Direct-read the exact Thread successfully and confirm exact project/role.
2. Confirm the original bounded assignment reached a terminal transport state
   and is not still running in background.
3. Confirm the primary body is missing and no complete, consistent Delivery
   Receipt can restore PASS/FAIL/BLOCKED.
4. Perform at most one controlled `REDELIVER` of the already-generated compact
   summary, with no development, tests, build, network, Provider, or new role.
5. Confirm redelivery also completes/returns idle with empty assistant body, no
   tool records, and no PASS/FAIL/BLOCKED conclusion.
6. Confirm Git did not change and a quiescent exact-checkout ReadOnly Guard is
   `READ_ONLY_CONFIRMED`.

Record Thread ID, Project ID, normalized role, first failure run, retry run,
observed state, direct-read/output/ReadOnly evidence, detection time, reason,
and a stable incident ID with `MarkDeliveryDegraded`. The first/retry run fields
identify primary delivery and redelivery, never two executions. Do not retry
indefinitely.

## Verified replacement

Verified `Degraded` joins the existing replacement gates without weakening
Stale, contamination, material-role-change, or explicit-user gates.

1. Search the exact project and normalized role for another healthy accessible
   task; adopt it before creating anything.
2. If none exists, create exactly one replacement for the incident.
3. Preserve `ReplacesThreadId`, incident ID, and full lineage.
4. Do not delete or call the old task successfully completed. Do not remove its
   Worktree/Branch, and do not create a coding Worktree for a read-only role.

One incident permits one adopted-or-created replacement. If it also fails,
record channel unavailability; never create `Architect 2`, `Architect 3`, or a
replacement chain.

## Replacement health check

Before sending repository context or the real Architecture Packet, ask the
replacement to return only visible text equivalent to:

```text
Status: HEALTH_OK
Role: <normalized role>
Project: <exact project>
```

It must not read the repository, call tools, or perform role analysis. Visible
matching text is PASS; record it with `RecordReplacementHealth`. Completed/idle
with empty body and no tools is FAIL: record
`VISIBLE_THREAD_DELIVERY_UNAVAILABLE`, set `CHANNEL_UNAVAILABLE`, and stop
replacement creation.

## Current-task safe fallback

When both original and the only replacement fail delivery, the current
Coordinator may fulfill a bounded read-only architecture decision only if it
can obtain all required evidence, has not edited the affected production code
in the same bounded run, no independent Security sign-off is required, the
decision is reversible/non-destructive, major writer conflict is absent, and
the user did not require an independent Architect.

Before analysis, state `ARCHITECT_SPECIALIST_CHANNEL_UNAVAILABLE` and start the
ReadOnly Guard. Reuse the existing capability evidence and architecture
acceptance contract. Return:

```yaml
Status:
Decision:
AffectedInterfaces:
AllowedDeveloperScope:
ForbiddenDeveloperScope:
CompatibilityConstraints:
RequiredTests:
ArchitectureConsistencyCriteria:
ScopeEscalation:
ReadOnlyGuard:
```

Finish only when the guard is `READ_ONLY_CONFIRMED`. Report
`Coordinator fallback`, never `Architect PASS` or independent review.

Fallback is forbidden for Security sign-off, authentication/credential
architecture, irreversible or destructive database migration, production
deployment authorization, unresolved major multi-writer architecture conflict,
a Coordinator that edited the affected production code in the same run, or an
explicit requirement for an independent Architect. Return `BLOCKED` until the
visible specialist channel recovers.

## Evidence reuse

Reuse a prior Existing Capability Check only when its exact Baseline SHA and
scope remain valid. Replacement or fallback alone does not trigger a new scan.
If baseline, interface, owner, permission, or scope changed, use the existing
Packet invalidation/CapabilityCheckRefresh rules; otherwise do not repeat a
repository-wide scan or the same capability check.

## Final reporting

Add this compact block to every routed task affected by delivery recovery:

```yaml
ThreadDelivery:
  Role:
  OriginalThread:
  DeliveryStatus: HEALTHY | DEGRADED | REPLACED | CHANNEL_UNAVAILABLE
  RetryCount:
  Replacement:
  ReplacementHealth:
  DeliveryReceipt:
  ReconciliationStatus:
  Acknowledged:
  FallbackUsed:
  FallbackReason:
```

Only a return that satisfies the role contract counts as delivery success.
