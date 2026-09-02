# V2 in-place upgrade and Canary runbook

## Gate 0 — exact baseline

Resolve the real `auto-visible-team-router` repo and installed Skill. Require a
clean working tree and record exact HEAD SHA, branch, origin, V1 VERSION,
registry hashes, installed Skill hash, and managed AGENTS block/hash. Confirm the
rollback baseline exists on the remote.

Create `codex/v2-workstream-router`. Do not edit main directly.

## Gate 1 — V2 repository replacement

Keep repo and Skill identity `auto-visible-team-router`; set VERSION `2.0.0`.
Remove/rewrite old references, tests, and scripts whose semantics conflict with
V2. Do not leave two reachable routing policies.

## Gate 2 — offline engineering

Required:
- Python/static validation;
- PowerShell parser/syntax validation;
- management-script tests in isolated temporary CODEX_HOME;
- registry lifecycle tests;
- JSON/schema validation;
- route acceptance fixtures;
- migration safety tests;
- `git diff --check`.

No real API/provider/credential use.

Result: `V2_OFFLINE_ENGINEERING_PASS`.

## Gate 3 — in-place SHADOW install

Back up installed V1 state, then install V2 under the same canonical Skill
identity. Archive old V1 registry; initialize fresh V2 workstream registry.
Replace V1 AGENTS block with one V2 SHADOW block. Verify exactly one router
block and no project Thread/Worktree side effect.

Result: `V2_SHADOW_INSTALL_PASS`.

## Gate 4 — platform-adapted synthetic Canary

The r1-r4 automatic visible-binding experiments are frozen. Their evidence is
preserved in `platform-capability-history.md`. Do not run r5/r6, extend waits,
guess a `clientThreadId`, infer binding from directory/HEAD names, or claim a
historical Worktree.

Current capability decision:

```text
AUTO_VISIBLE_WORKTREE = UNSUPPORTED_BY_CURRENT_TOOL_SURFACE
reason = THREAD_CREATION_PLATFORM_LIMITATION
```

Run the platform-adapted synthetic gate entirely offline:

1. tiny LOCAL -> `CURRENT_THREAD`, no extra Agent;
2. SERIAL_1 -> `CURRENT_THREAD` or a capability-safe one-Agent backend;
3. logical PARALLEL_2 with no safe parallel backend ->
   `SERIALIZED_FALLBACK`;
4. logical PARALLEL_3 with no safe backend -> serialized waves;
5. overlapping writer scope -> serial;
6. credential/auth/permission scenario -> QA + Security;
7. Context Packet, Context Delta, compact delivery, Registry, and one-writer
   boundaries remain valid;
8. `AUTO_VISIBLE_WORKTREE` stays unsupported and no automatic Thread creation
   is called;
9. unknown/historical Worktrees remain preserved and unowned.

`COLLAB_SUBAGENT` may be selected for bounded read-only work only when its
independent value is explicit. Current collaboration Agents share one working
tree, so they are not a safe parallel coding backend.

When the user explicitly requests multiple visible Codex tasks, return
`READY_FOR_MANUAL_VISIBLE_DISPATCH`. Adoption occurs only after the user creates
the tasks and real Thread ID plus Repository Containment both pass.

Result: `V2_PLATFORM_ADAPTED_SYNTHETIC_PASS`.

This Gate proves safe routing degradation, not automatic visible-task support.

## Gate 5 — local ACTIVE promotion

Replace SHADOW block with ACTIVE V2 block, verify V1 routing instructions are
absent, set V2 runtime ACTIVE, then start a fresh Codex task/session.

Result: `V2_LOCAL_ACTIVE_PASS`.

## Gate 6 — bounded real-project Canary

Choose one low/medium-risk existing-project task with clear acceptance,
reversible local scope, and no real secret/provider spending unless separately
authorized.

Record route, Threads, Workstreams, Read Scope, Worktrees, exact SHAs, tests,
QA cycles, integration, wall time, and authoritative usage if exposed; otherwise
usage is `Unknown`.

Result: `V2_REAL_CANARY_PASS | FAIL | BLOCKED`.

If no suitable task exists, stop at `READY_FOR_USER_SELECTED_REAL_CANARY`.

## Gate 7 — finalize repository

After PASS: final regression, `git diff --check`, commit V2 on upgrade branch,
push branch, verify remote SHA. Merge/fast-forward main only when all gates pass
and current authorization permits it. Never force push.
