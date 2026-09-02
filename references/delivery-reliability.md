# Delivery reliability

## Purpose

Keep "work finished" separate from "Coordinator received a trustworthy result."

V2 reuses the compact reliability idea without creating a second project
narrative.

## Compact Receipt

```yaml
TaskId:
BatchId:
WorkstreamId:
ThreadId:
DeliveryStatus:
ResultStatus: PASS | FAIL | BLOCKED
CommitSHA:
GitClean:
TestsSummary:
EvidenceSummary:
Timestamp:
ReceiptHash:
```

`TestsSummary` and `EvidenceSummary` are each capped at 1200 characters and
12 lines.

Do not store:
- prompts;
- model reasoning;
- complete chat history;
- API keys/passwords/tokens;
- raw Provider responses;
- large logs.

## State machine

```text
DISPATCHED
  -> RUNNING
  -> WORK_COMPLETED
  -> DELIVERY_PENDING
  -> DELIVERED
  -> ACKNOWLEDGED
```

`completed` transport state is not automatically PASS.

## Normal close

1. Workstream finishes work/evidence.
2. Compact Receipt is recorded if registry writes are authorized.
3. Coordinator receives/reads compact result.
4. Reconcile Task/Batch/Workstream IDs, result, SHA, tests, evidence.
5. Exact agreement -> DELIVERED.
6. Coordinator consumes result -> ACKNOWLEDGED.

## Missing body

Order:
1. exact-read same visible Thread;
2. accept valid compact final body;
3. inspect matching V2 Receipt;
4. if still absent, request one REDeliver-only summary.

## Redelivery

One attempt only.

It must not:
- modify code;
- rerun tests/build;
- call network/Provider;
- spend real API usage;
- create a replacement implementer.

If still unavailable, return `MANUAL_VISIBLE_THREAD_HANDOFF` or bounded
delivery recovery according to risk.

## Conflict

If primary body and Receipt conflict on critical fields, record
`DELIVERY_EVIDENCE_CONFLICT` and do not choose a winner automatically.
