# Risk-based gates

## Principle

Independent verification is valuable when failure cost or self-verification
limits justify another model context.

It is not a ritual attached to every Feature.

## Architect Gate

Architect is required only when at least one applies:

- new system boundary;
- long-lived public/shared contract with material design choice;
- two or more coding Workstreams need one new/fundamentally changed interface;
- large refactor that changes ownership/boundaries;
- significant data/AI/security architecture;
- several credible designs have long-term consequences.

Not sufficient by itself:
- many files;
- cross-layer UI/Core;
- normal endpoint/page/settings change;
- a failed test.

Architect is read-only by default and returns a decision/contract.

## QA Gate

Independent QA is normally required for:

- concurrency/cancellation/recovery semantics;
- credential/auth/permission changes;
- schema/data migration;
- critical persistence/integrity;
- release candidate;
- integration of multiple coding Workstreams;
- important public/shared contract change;
- high-impact bug;
- repeated repair/testing failure;
- implementation that owner cannot independently validate.

Independent QA is normally not required only because:
- >1 file changed;
- UI and Core both changed;
- task is called medium/large;
- a numeric complexity score would be high.

### Low/medium-risk owner verification

Owner may close with:
- targeted tests;
- build/typecheck/lint as relevant;
- exact diff/SHA evidence;
- acceptance evidence.

### Multi-lane default

Prefer:

```text
A ─┐
B ─┼→ Integration Candidate → Independent QA
C ─┘
```

rather than QA after every low/medium-risk lane.

The Workstreams may be executed concurrently or by serialized fallback. The
post-integration QA trigger comes from multiple bounded outputs being combined,
not from the number of visible tasks.

A lane may still require pre-integration QA when its own risk is high.

QA verifies exact evidence, remains read-only, and never repairs code then passes
its own repair.

## Security Gate

Add Security when this change affects:
- credentials/secrets;
- authentication;
- authorization/permissions;
- privacy/sensitive data;
- external trust boundary;
- code execution boundary;
- encryption/key handling;
- consequential network exposure.

Security is not required for ordinary UI/state changes with unchanged trust
boundaries.

## Reviewer Gate

Add Reviewer for:
- ambiguous correctness not covered by tests;
- consequential design/code review;
- repeated QA rejection;
- owner cannot independently evaluate the implementation.

Reviewer is not a permanent companion.

## Research Gate

Use bounded Research only when an external/technical fact must be established
before a decision. Research owns evidence, not implementation.

## Gate matrix

```yaml
risk_gate_decision:
  architect:
    required: true|false
    reason:
  qa:
    required: true|false
    phase: pre_integration | post_integration | none
    reason:
  security:
    required: true|false
    reason:
  reviewer:
    required: true|false
    reason:
```
