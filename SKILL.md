---
name: auto-visible-team-router
description: V2 platform-adaptive Workstream router for software engineering. Separate bounded logical routing from execution backend selection while preserving exact-SHA, one-writer-per-scope, bounded context, risk-based verification, and non-destructive Git rules.
---

# Auto Visible Team Router V2

Act as the coordinator in the current user-visible Codex task. Optimize for the
fewest independent model contexts that can safely deliver the requested result.

The primary unit is a **Workstream**, not a permanent job title.

Logical routing is separate from execution placement. A `PARALLEL_2` decision
describes two independent deliverables; it does not require two visible tasks.

A Workstream is one bounded, independently describable deliverable with:
- one owner;
- one write authority;
- explicit dependencies;
- observable acceptance;
- a short lifecycle scoped to the current batch.

Long-term project memory belongs in code, Git, tests, contracts, checkpoints,
and verified registries. A Codex Thread is temporary working memory.

## 0. Mode gate — read this first

Read [references/modes-and-mutual-exclusion.md](references/modes-and-mutual-exclusion.md)
before routing.

Default mode is `SHADOW`.

During upgrade/validation use `SHADOW`; after the full V2 promotion gate passes, production mode is `ACTIVE`.

If V2 runtime state is missing, unreadable, ambiguous, or conflicting, treat it
as `SHADOW`.

### SHADOW

In SHADOW:
- do not create or adopt specialist Threads;
- do not create Worktrees or Branches;
- do not edit product code;
- do not change V1 state;
- do not write V2 registry or telemetry unless the user explicitly authorized
  local V2 telemetry;
- produce only a compact proposed V2 route.

SHADOW may inspect only the bounded evidence necessary to explain the proposed
route. It must not perform a repository-wide scan merely to make the proposal
look complete.

### CANARY / ACTIVE

Never run V2 as an active router while V1 is also actively routing the same
task/project. If exclusivity is not proven, return `DUAL_ROUTER_BLOCKED`.

`CANARY` is batch-scoped and must match the authorized project/batch.

`ACTIVE` is not enabled by this package by default. It requires separate real
Codex environment authorization after Shadow and Canary evidence.

## 1. Applicability

Use this workflow only for real engineering work: implementation, debugging,
architecture changes, integration, migration, testing, or release preparation.

Do not form a V2 team for:
- ordinary chat or explanation;
- translation;
- simple file lookup;
- tiny text/config changes;
- one isolated low-risk edit that the current task can safely finish.

Routing never grants permission to push, deploy, publish, delete user data,
weaken security, spend money, use real credentials, or expand scope.

## 2. Work-first routing

Do not begin with roles or a numeric complexity band.

Read:
1. [references/workstream-routing.md](references/workstream-routing.md)
2. [references/dependency-planning.md](references/dependency-planning.md)

Then answer, in this order:

1. What observable deliverables are required?
2. Which deliverables depend on which others?
3. Can one owner safely finish the complete vertical slice?
4. Would a second coding lane have a distinct deliverable and disjoint write
   authority?
5. Is the dependency/contract stable enough for parallel work?
6. Does parallel execution materially repay coordination/integration cost?
7. Which risk gates are independently justified?

### Hard extra-agent rule

Every additional Agent must own an independent, describable, independently
checkable deliverable.

If no such deliverable exists, do not create that Agent.

A module, file count, framework, or job title is not a deliverable.

## 3. Route decisions

Use one of:

- `LOCAL` — current task owns implementation; no extra visible task.
- `SERIAL_1` — one task-scoped Workstream is useful; no parallel coding lane.
- `PARALLEL_2` — exactly two independent coding Workstreams.
- `PARALLEL_3` — exactly three independent coding Workstreams.
- `PLAN_FIRST` — a contract/architecture decision must be frozen before coding.
- `BLOCKED` — safety, dependency, authorization, or router exclusivity is not
  satisfied.

Default to `LOCAL` or `SERIAL_1`.

`PARALLEL_2` and `PARALLEL_3` are logical plans. If the current platform has no
safe parallel backend, preserve the Workstream boundaries and execute them with
`SERIALIZED_FALLBACK` or `SERIALIZED_WAVES`. Parallel execution is an
optimization, not a correctness prerequisite. Block only when the requested
correctness evidence itself requires real concurrency.

The default maximum number of simultaneous coding Workstreams is **3**.
Do not increase it because the UI can display more windows.

## 3A. Execution backend selection

Read [references/execution-backends.md](references/execution-backends.md) after
logical routing and before dispatch.

Execution backends are independent from logical routes:

- `CURRENT_THREAD` — default; owns LOCAL and safe serial execution.
- `COLLAB_SUBAGENT` — only when the exposed capability has independent value.
  Current collaboration Agents share the same working tree, so coding
  parallelism is forbidden; bounded Research, Reviewer, or read-only analysis
  may still be considered.
- `MANUAL_VISIBLE_WORKTREE` — optional user-assisted backend. Use only when the
  user explicitly asks for multiple visible Codex tasks. Return
  `READY_FOR_MANUAL_VISIBLE_DISPATCH`, then adopt only a real Thread whose
  repository containment passes.
- `AUTO_VISIBLE_WORKTREE` — `UNSUPPORTED` with reason
  `THREAD_CREATION_PLATFORM_LIMITATION`. Do not call automatic app-native
  Thread creation for repo-bound coding Workstreams.

Selection order is `CURRENT_THREAD`, capability-safe `COLLAB_SUBAGENT`,
user-requested `MANUAL_VISIBLE_WORKTREE`, then `AUTO_VISIBLE_WORKTREE` (currently
disabled). Never create extra context for visual effect.

## 4. Batch snapshot

Before delegating any coding Workstream, establish one compact batch snapshot:

```yaml
batch_id:
project_key:
project_root:
objective:
baseline_sha:
branch:
worktree:
milestone:
known_constraints:
relevant_contracts:
existing_capability_evidence:
```

This snapshot is a bounded index, not a replacement for real files/Git/tests.

Do not resend the complete project history to each Workstream.

### Project identity gate

Read [references/project-identity.md](references/project-identity.md) before
opening a Batch.

Resolve identity in this order:

1. app-native Project ID -> `id:<projectId>`;
2. canonical Git root + exact HEAD -> `git:<canonical-git-root>`;
3. unambiguous canonical local path -> `path:<canonical-path>`.

`thread.projectId` is preferred evidence, not a hard requirement. A local Git
repository remains valid without a Project ID or remote. Return
`PROJECT_IDENTITY_BLOCKED` only when all three identity sources are unavailable
or ambiguous. Never identify a project from its display title alone.

### Repository / Worktree containment gate

Project identity is not Thread checkout identity. Before adopting a manually
created visible Coordinator or Workstream, read
[references/repository-containment.md](references/repository-containment.md)
and run `scripts/Resolve-RepositoryContainment.ps1` against its real cwd.

Do not require `Thread cwd == CanonicalGitRoot`. A related Git Worktree at a
different path is legal only when canonical `git-common-dir`, canonical
worktree inventory or equivalent app evidence, starting lineage, and dirty
attribution all pass. Similar names, equal remote, or equal HEAD are not proof.

## 5. Task-scoped Threads and current-task Workstreams

Read [references/thread-lifecycle.md](references/thread-lifecycle.md).

The primary identity key is:

```text
project_key + batch_id + workstream_id
```

Do not discover/reuse Threads by permanent role such as `Developer`, `QA`,
`Architect`, or `Security`.

Reuse a Thread only for the same batch/workstream or its bounded repair /
delivery recovery.

A new milestone or unrelated batch defaults to a fresh Workstream Thread.

`CURRENT_THREAD` may execute several Workstreams serially. Logical identity
still remains `project_key + batch_id + workstream_id`; switch with one bounded
Workstream Packet and compact checkpoint, and never mix simultaneous ownership
scopes in one step.

## 6. Context delegation

Before assigning a Workstream, read
[references/context-delegation.md](references/context-delegation.md).

Send one Workstream Packet containing only:
- objective;
- baseline;
- owned paths/scope;
- starting evidence;
- relevant contracts;
- dependencies;
- constraints;
- acceptance;
- tests;
- risk flags;
- compact return contract.

Developer-like coding owners start at Read Scope 1 and widen only on evidence.

After the first Packet, repairs use Context Delta rather than repeated project
narrative.

## 7. Capability, not permanent role

Use capability labels only to describe what the Workstream needs, for example:

- Fullstack
- AI
- Voice
- Windows
- Database
- DevOps
- Architect
- QA
- Security
- Reviewer
- Research

Capability labels do not create a Thread by themselves.

One owner may cover several capabilities when one vertical slice is safer and
cheaper to understand as a whole.

## 8. Risk-based gates

Read [references/risk-gates.md](references/risk-gates.md).

Architect, QA, Security, Reviewer, and Research are **gates/capabilities**, not
permanent companions.

Do not add independent QA merely because a change:
- touches several files;
- crosses UI/Core layers;
- is called a Feature;
- would have been V1 Level 2.

Prefer owner verification for low/medium-risk bounded work.

Prefer one post-integration independent QA for multiple low/medium-risk lanes
rather than QA after every lane.

Independent QA remains required when risk evidence justifies it.

QA never repairs writer code and then passes its own repair.

## 9. Git and write safety

Before any real CANARY/ACTIVE coding delegation, read
[references/git-worktree-safety.md](references/git-worktree-safety.md).

Hard rules:
- one active writer per owned file/scope;
- parallel writers require disjoint write ownership;
- unresolved ownership overlap serializes;
- a new Worktree is justified only for genuine parallel coding;
- the current tool surface does not authorize automatic visible Worktree
  creation;
- one coding lane normally stays in/reuses one safe checkout;
- default V2 Router-managed Worktree Budget is 3;
- read-only gates do not receive a new coding Worktree by default;
- never delete unknown/adopted/user Git objects to manufacture capacity.

## 10. Integration

The current Batch Coordinator is the default Integration Owner.

Integration is a distinct phase only when multiple Workstream outputs or SHAs
must be combined.

Before integration:
- verify each exact SHA;
- verify write ownership did not overlap unexpectedly;
- verify dependency contracts still match;
- fail closed on ambiguous lineage.

Then:
- integrate;
- run targeted integration checks;
- apply risk-based QA/Security gates;
- run proportionate regression.

Do not create a second Integration Agent unless it has a distinct necessary
deliverable that the current Coordinator cannot safely own.

## 11. Delivery reliability

Read [references/delivery-reliability.md](references/delivery-reliability.md)
after every terminal visible Workstream.

Keep work completion separate from result delivery.

Use compact Receipt -> reconciliation -> ACK. A delivery retry may redeliver the
already-generated compact result once; it must not rerun implementation, tests,
network calls, or real Provider requests.

## 12. Existing capability guard

For an existing project, perform one bounded Existing Capability Check when the
request might duplicate functionality.

Start from likely owners/callers/contracts/tests. Reuse that evidence through
all Workstream Packets.

Do not order every lane to independently rediscover whether the same capability
already exists.

A duplicate file name or class name is not proof of duplicate behavior.

## 13. Shadow/A-B telemetry

Read [references/telemetry-ab.md](references/telemetry-ab.md).

Never estimate Token savings from file count or Thread count.

Record model/token/credit usage only when Codex exposes authoritative usage for
the measured run; otherwise record `Unknown`.

Structural metrics may include:
- model contexts / visible Threads started;
- repository-wide reads;
- read-scope escalations;
- test/build runs;
- QA cycles;
- repair loops;
- integration passes;
- wall-clock duration;
- user-visible defects.

## 14. V1 coexistence and migration

Read [references/migration-v1.md](references/migration-v1.md).

V1.3.3 remains the exact Git/GitHub rollback baseline; after V2 promotion it is no longer a co-running production router.

Do not reinterpret V1 permanent-role registry entries as V2 Workstream identity. Archive V1 registry state before initializing V2 state.

A real V2 Canary must have a single active router. V1 may be temporarily
disabled for that bounded Canary, but not deleted. Rollback is re-enable V1 and
return V2 to SHADOW/DISABLED.

## 15. Evidence-backed close

Return a compact summary:

```yaml
v2_result:
  mode:
  logical_route: LOCAL | SERIAL_1 | PARALLEL_2 | PARALLEL_3 | PLAN_FIRST | BLOCKED
  execution_backend: CURRENT_THREAD | COLLAB_SUBAGENT | MANUAL_VISIBLE_WORKTREE | AUTO_VISIBLE_WORKTREE | NONE
  execution_mode: DIRECT | SERIAL | PARALLEL | SERIALIZED_FALLBACK | SERIALIZED_WAVES | READY_FOR_MANUAL_VISIBLE_DISPATCH | PLAN_FIRST | BLOCKED
  batch_id:
  workstreams:
  dependencies:
  write_ownership:
  risk_gates:
  threads_created:
  worktrees_created:
  exact_shas:
  tests:
  integration:
  telemetry:
  unresolved_risks:
```

Do not output hidden chain-of-thought. Give decisions and evidence only.

## 16. Fixed V2 boundary

V2 does not:
- promise a Token-saving percentage;
- automatically select a cheaper model;
- weaken security to save usage;
- auto-push/deploy/publish;
- use real credentials without separate authorization;
- erase the V1 rollback baseline;
- silently reinterpret V1 role-thread registry entries as V2 workstreams;
- auto-enable itself globally;
- run two active routers for one task;
- create visible windows merely for appearance;
- call `AUTO_VISIBLE_WORKTREE` while the capability matrix marks it
  `UNSUPPORTED`;
- block an ordinary Feature only because a parallel/visible backend is
  unavailable;
- turn every module into a Workstream.

Read [references/acceptance-tests.md](references/acceptance-tests.md) before
modifying or promoting this Skill.
