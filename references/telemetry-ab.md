# Shadow and A/B telemetry

## Goal

Measure whether V2 actually reduces coordination/usage without weakening
delivery quality.

Do not estimate Token savings.

## Allowed measurements

Record authoritative model/token/credit usage only when Codex exposes it for the
specific run. Otherwise:

```text
usage = Unknown
```

Never derive Token count from:
- file count;
- text length;
- Thread count;
- model name;
- duration.

## Structural metrics

```yaml
metrics:
  logical_route:
  execution_backend:
  execution_mode:
  parallel_degraded:
  visible_threads_started:
  model_contexts_started:
  coding_lanes:
  repository_wide_reads:
  read_scope_escalations:
  tool_calls_if_authoritative:
  build_runs:
  test_runs:
  qa_cycles:
  repair_cycles:
  integration_passes:
  wall_clock_seconds:
  user_visible_defects:
  usage_tokens_or_credits: value | Unknown
```

## Shadow comparison

In SHADOW, V2 proposes a route but does not implement.

Compare:
- V1 actual route/Agent count where observable;
- V2 proposed route;
- predicted duplicate-context structure (Low/Medium/High only);
- risk gates each would invoke.
- logical route separately from actual execution backend.

Do not report hypothetical Token savings.

## Real A/B

Use comparable bounded tasks, ideally:
1. small low-risk;
2. medium cross-layer;
3. high-risk/integration.

Record baselines and acceptance before runs.

Do not run V1 and V2 simultaneously on the same writable repo/task.

## Promotion evidence

V2 is a promotion candidate only if evidence shows:
- no dual-router incident;
- no write-ownership collision;
- no missing required QA/Security gate;
- no unexplained regression increase;
- fewer/equal unnecessary Agent contexts on small/medium tasks;
- acceptable wall-clock behavior;
- authoritative usage is better when such data is actually available.

No fixed savings percentage is required in advance.
