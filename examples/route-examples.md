# Route examples

## Example 1 — small bug

Requirement:

> Fix one settings label typo.

Result:

```yaml
logical_route: LOCAL
execution_backend: CURRENT_THREAD
execution_mode: DIRECT
deliverables:
  - fix label and verify targeted UI check
risk_gates:
  architect: false
  qa: false
  security: false
```

No specialist Thread.

## Example 2 — contained cross-layer feature

Requirement:

> Add a model choice to Settings and propagate it to the existing Provider config.

Even if several files/layers change, one owner can safely own the vertical slice.

```yaml
logical_route: LOCAL
execution_backend: CURRENT_THREAD
# or SERIAL_1 if a fresh isolated context is materially useful
```

No independent QA unless actual risk evidence requires it.

## Example 3 — two independent sides of frozen contract

Requirement:

> Core emits model-state event; Island displays it.

Existing/frozen event contract is known.

```text
Core producer ───┐
                 ├→ Integration → QA
Island consumer ┘
```

```yaml
logical_route: PARALLEL_2
execution_backend: CURRENT_THREAD
execution_mode: SERIALIZED_FALLBACK
qa: post_integration
```

The logical lanes remain independent, but the current platform has no proven
isolated automatic coding backend. Execute Core, checkpoint, execute Island,
then integrate. If the user explicitly requests visible tasks, return
`READY_FOR_MANUAL_VISIBLE_DISPATCH` instead.

## Example 4 — contract not frozen

Same requirement, but protocol event schema must be invented.

```text
PLAN_FIRST: freeze event contract
        ↓
Core producer + Island consumer
        ↓
Integration QA
```

Architect is used only if the contract decision is genuinely architectural.

## Example 5 — credential cancellation flow

Requirement touches:
- credential lease;
- cancellation;
- Provider boundary.

Likely:

```yaml
logical_route: SERIAL_1
execution_backend: CURRENT_THREAD
execution_mode: SERIAL
risk_gates:
  architect: false-or-evidence-based
  qa: true
  security: true
```

Do not parallelize merely because several modules exist.

## Example 6 — 10 unrelated backlog items

If 10 tasks are truly independent, V2 still defaults to a bounded batch:

```text
Logical Wave 1: A / B / C
Logical Wave 2: D / E / F
Execution: serialized Workstream checkpoints unless a safe backend is proven
...
```

Maximum default coding lanes remains 3. This controls context/integration
pressure rather than maximizing visible windows.
