# Delivery reliability and reconciliation

Read this reference after every visible specialist reaches a terminal transport
state, and before treating `completed` as a role result or starting V1.3.2
delivery-degradation recovery.

## Contents

- [Truth and platform boundary](#truth-and-platform-boundary)
- [Delivery Receipt](#delivery-receipt)
- [State machine](#state-machine)
- [Normal close](#normal-close)
- [Delivery reconciliation](#delivery-reconciliation)
- [Controlled redelivery](#controlled-redelivery)
- [Conflict and safety](#conflict-and-safety)
- [Manual handoff](#manual-handoff)

## Truth and platform boundary

`completed` is only a task transport state. It is not `PASS`, `FAIL`, or
`BLOCKED`, and it is not proof that the Coordinator received the result.

Use this truth order:

1. exact visible specialist final message obtained from the task event or an
   exact `read_thread`;
2. a valid compact Delivery Receipt in the existing Thread Registry;
3. exact Git, test, ReadOnly Guard, and project evidence referenced by either;
4. a single compact redelivery;
5. `MANUAL_VISIBLE_THREAD_HANDOFF` when the platform channel and receipt are
   both unavailable or conflicting.

Current Codex task tools support waiting, exact task reads, and follow-up
messages, but do not expose an app-owned atomic Receipt/ACK transaction. The
Registry mechanism is therefore a Skill-managed reliability layer, not a claim
of exactly-once platform delivery. Never hide this `PLATFORM_LIMITATION`.

## Delivery Receipt

Extend the existing Thread Registry schema 2 `delivery` object; do not create a
second Registry or copy chat history. Use `packet_id` as `TaskId` for the bounded
assignment unless a stable exact task identifier already exists.

A compact Receipt contains only:

```yaml
TaskId:
ThreadId:
Role:
DeliveryStatus:
ResultStatus: PASS | FAIL | BLOCKED
CommitSHA: optional
ParentSHA: optional
GitClean: true | false | null
TestsSummary:
EvidenceSummary:
Timestamp:
ReceiptHash:
```

The Specialist records the Receipt after work and evidence already exist, then
returns the matching compact result. The hash detects accidental mutation; it
does not make self-reported evidence independently authoritative. QA and Git
gates remain separate.

Summaries are capped at 1200 characters and 12 lines each. They describe test
outcomes and evidence locations, not logs, prompts, responses, or reasoning.

## State machine

Use these monotonic states:

```text
DISPATCHED
  -> RUNNING
  -> WORK_COMPLETED
  -> DELIVERY_PENDING
  -> DELIVERED
  -> ACKNOWLEDGED
```

- `WORK_COMPLETED`: the role finished its work; delivery is not yet proven.
- `DELIVERY_PENDING`: a Receipt exists or reconciliation/redelivery is needed.
- `DELIVERED`: primary body and/or Receipt passed reconciliation.
- `ACKNOWLEDGED`: Coordinator accepted the reconciled `PASS`, `FAIL`, or
  `BLOCKED` result.
- `DELIVERY_EVIDENCE_CONFLICT`: evidence disagrees; it cannot transition to ACK.

Use `SetDeliveryState`, `RecordDeliveryReceipt`, `ReconcileDelivery`,
`RequestRedelivery`, and `AcknowledgeDelivery`. Direct `DELIVERED` or
`ACKNOWLEDGED` assignment is forbidden.

## Normal close

1. Specialist reaches `WORK_COMPLETED` without changing the original Packet.
2. Specialist records a compact Receipt and enters `DELIVERY_PENDING`.
3. Coordinator receives the compact primary body.
4. Coordinator compares TaskId, ThreadId/Role, ResultStatus, SHA/Git state when
   applicable, TestsSummary, and EvidenceSummary with the Receipt.
5. Exact agreement becomes `DELIVERED`.
6. Coordinator consumes the formal result and records `ACKNOWLEDGED`.

Normal Developer and QA completion both follow this close. Receipt presence
does not turn Developer self-report into QA PASS.

## Delivery reconciliation

When the wait result says `completed` but the primary body is missing:

1. exact-read the same Thread before sending any message;
2. accept a visible compact final body if it satisfies the role return contract;
3. inspect the same Thread Registry entry for a complete Receipt;
4. verify Receipt hash, TaskId, ThreadId, Role, status, compactness, and safety;
5. if valid, restore its formal `PASS`, `FAIL`, or `BLOCKED` result as
   `DELIVERED`, then ACK;
6. if absent or incomplete, request one controlled redelivery.

This path is `DELIVERY_RECONCILIATION`. It must precede replacement, Coordinator
fallback, or a request for the user to copy text manually.

## Controlled redelivery

The only retry is `REDELIVER`: resend the already-generated compact summary and,
if the original Receipt write did not persist, record that same summary once.

The retry must not:

- develop or modify code;
- run tests or builds;
- use network access or a Provider;
- repeat real API consumption;
- rerun Developer/QA work;
- create another Specialist.

Use a prompt equivalent to:

```text
REDELIVER only the already-generated compact delivery summary. Do not re-run
work, tests, builds, network, providers, or development.
```

`RequestRedelivery` permits one attempt and then returns
`DELIVERY_RETRY_EXHAUSTED`. A retry is never a Context Delta because no work,
scope, SHA, tests, or evidence changed.

## Conflict and safety

Compare every applicable critical field. If the primary body and Receipt differ
on TaskId, Role, ResultStatus, CommitSHA, ParentSHA, GitClean, TestsSummary, or
EvidenceSummary, record `DELIVERY_EVIDENCE_CONFLICT`, do not ACK, do not choose a
winner, and require exact-task inspection.

Reject a Receipt or summary containing API keys, passwords, secrets,
Authorization/Bearer data, credentials, prompt/completion/reasoning bodies, raw
Provider responses, raw SSE, large logs, or complete chat history. Never write
rejected content to the Registry.

## Manual handoff

Do not remove `MANUAL_VISIBLE_THREAD_HANDOFF`. Use it only after exact direct
read, valid Receipt reconciliation, and the one controlled redelivery cannot
produce a trustworthy result, or when conflict requires human inspection.

If redelivery is also empty, continue into
[visible-thread-delivery-recovery.md](visible-thread-delivery-recovery.md) for
Degraded/replacement rules. Never recreate work merely to repair delivery.
