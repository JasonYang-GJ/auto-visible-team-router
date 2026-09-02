# Workstream routing policy

## 1. No numeric team-size bands

V2 does not use file count or a complexity score to decide Agent count.

Complexity may increase risk, but risk and team size are different questions.

A large contained vertical slice may still be best with one owner.

## 2. Route factors

Evaluate:

```yaml
routing_factors:
  deliverables:
  dependency_shape:
  write_overlap:
  contract_stability:
  owner_can_finish_vertical_slice:
  parallel_time_benefit:
  integration_cost:
  duplicate_context_risk:
  blast_radius:
  verification_need:
```

## 3. Deliverable definition

A valid deliverable has:
- an observable outcome;
- a bounded owner;
- a bounded write scope or read-only scope;
- acceptance criteria;
- a terminal result.

Examples:

Valid:
- "Core emits canonical model-state event through existing protocol."
- "Island consumes frozen model-state event and renders state."
- "Migration converts schema 7 -> 8 and proves rollback/forward behavior."

Invalid:
- "Backend work."
- "Architecture stuff."
- "Look at the project."
- "QA because the task is complex."

## 4. Single-owner test

Before creating a second coding Agent, ask:

> Can one owner safely implement and verify the complete vertical slice without
> a material reason to split context or write authority?

If YES, use `LOCAL` or `SERIAL_1`.

Multi-file, multi-module, or cross-layer alone does not fail the test.

## 5. Parallel Benefit Gate

`PARALLEL_2` or `PARALLEL_3` requires every lane to pass:

1. independent deliverable;
2. disjoint write ownership;
3. satisfied dependencies;
4. stable/frozen interface between lanes;
5. material wall-clock benefit;
6. bounded integration cost;
7. no duplicate-context pattern that erases the time benefit.

If any required property is unknown, serialize until it is known.

## 6. Decision table

### LOCAL

Use when:
- current task can safely own the whole bounded change;
- context is sufficiently clean;
- no distinct independent Agent value exists.

### SERIAL_1

Use when:
- a fresh task-scoped context is useful;
- one owner should still do the work;
- parallelism adds little value.

### PARALLEL_2 / PARALLEL_3

Use only for genuinely independent deliverables. These are logical routes, not
promises to create two or three model contexts.

Default cap: 3 coding lanes.

After selecting the logical route, apply
[execution-backends.md](execution-backends.md). If no safe parallel backend is
available, keep the route and run `SERIALIZED_FALLBACK` or
`SERIALIZED_WAVES`. Do not block an ordinary Feature merely because parallel
execution is unavailable.

### PLAN_FIRST

Use when:
- workstreams cannot safely start until an interface/contract/architecture
  decision is frozen.

The planning step may be performed by the Coordinator. Add an Architect only
when the decision meets the Architect gate.

### BLOCKED

Use for:
- dual-router ambiguity;
- unsafe Git state;
- unresolved ownership overlap;
- missing authorization;
- missing dependency/contract evidence that would make edits unsafe.

## 7. Duplicate-context risk

Classify:

- Low: different modules/evidence, little shared reading.
- Medium: some shared contract/background, mostly local work.
- High: lanes would reread/reconstruct much of the same project for little
  distinct output.

High duplicate-context risk strongly favors SOLO/SERIAL unless independent
verification is required by risk.

## 8. Structured route proposal

```yaml
route_proposal:
  mode: SHADOW | CANARY | ACTIVE
  logical_route: LOCAL | SERIAL_1 | PARALLEL_2 | PARALLEL_3 | PLAN_FIRST | BLOCKED
  execution_backend: CURRENT_THREAD | COLLAB_SUBAGENT | MANUAL_VISIBLE_WORKTREE | AUTO_VISIBLE_WORKTREE | NONE
  execution_mode: DIRECT | SERIAL | PARALLEL | SERIALIZED_FALLBACK | SERIALIZED_WAVES | READY_FOR_MANUAL_VISIBLE_DISPATCH | PLAN_FIRST | BLOCKED
  batch_id:
  objective:
  deliverables:
    - id:
      outcome:
      owner_capability:
      write_scope:
      read_start:
      dependencies:
      acceptance:
  parallel_gate:
    independent_deliverables:
    disjoint_writes:
    contracts_stable:
    time_benefit:
    integration_cost:
    duplicate_context_risk:
  backend_selection:
    safe_parallel_backend:
    parallel_degraded:
    manual_dispatch_required:
  risk_gates:
    architect:
    qa:
    security:
    reviewer:
```

Keep it compact. Do not expose chain-of-thought.
