# Dependency planning

## Goal

Parallelism is legal only when dependency order makes it safe.

Use the smallest useful DAG.

## Node types

- `PLAN` — decision/contract must be frozen.
- `CODE` — coding deliverable.
- `VERIFY` — independent gate.
- `INTEGRATE` — combine exact outputs.

## Dependency states

A dependency is:
- `SATISFIED`
- `FROZEN_CONTRACT`
- `UNRESOLVED`

A coding Workstream may start only when every hard dependency is SATISFIED or
represented by a verified frozen contract.

## Example

```text
A: freeze event contract
       ↓
B: Core producer ───┐
                    ├→ D: integration → E: QA
C: Island consumer ┘
```

B and C are logically parallel only after A. They run concurrently only when
backend selection proves isolated execution; otherwise execute B then C with a
compact checkpoint before integration.

## Write ownership

For each coding Workstream record:

```yaml
owned_scope:
  include:
  exclude:
shared_read_only_contracts:
```

If two active writers own the same file/path or cannot explain how overlapping
edits are prevented, do not parallelize them.

For `CURRENT_THREAD` serialized fallback, only one Workstream is active at a
time. Close or checkpoint its ownership before activating the next scope.

## Contract freeze

A frozen contract is evidence, not a verbal assumption.

Prefer:
- existing interface/schema/protocol file;
- accepted design decision committed or checkpointed;
- exact versioned spec.

If the interface is changing and two lanes need it, freeze it before parallel
coding.

## Replan trigger

Replan when:
- a lane discovers it must write outside ownership;
- a contract changes;
- a dependency proves false;
- integration cost becomes materially larger;
- a high-risk condition appears.

Do not silently expand a lane into another lane's ownership.

Use:

```yaml
replan:
  reason:
  affected_workstreams:
  old_dependency:
  new_dependency:
  action: SERIALIZE | REASSIGN | PLAN_FIRST | BLOCK
```
