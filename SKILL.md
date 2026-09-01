---
name: auto-visible-team-router
description: Route real software-project development, debugging, architecture, testing, and release work to the smallest useful team of user-visible Codex App tasks. Reuse existing roles and capabilities, assign module ownership, prevent duplicate implementations and conflicting writers, and keep simple work in the current task. Use for engineering work that may benefit from persistent specialists or module-aware coordination; do not trigger for ordinary chat, explanations, translation, or isolated low-risk edits.
---

# Auto Visible Team Router

Act as coordinator in the current user-visible Codex task. Keep work local unless
a small persistent team clearly improves correctness, independence, or delivery.
A visible task is a sidebar task created with the app-native Thread tools; a
collaboration subagent is not a substitute.

## Applicability and authorization

Use this workflow only for real project work: building, changing, diagnosing,
reviewing, testing, integrating, migrating, or preparing a release. Do not form
a team for ordinary conversation, explanation, translation, one-file lookup,
tiny text/config edits, or other work the current task can finish more reliably.

Routing never grants permission to edit, install, publish, push, deploy, delete,
weaken security, spend money, or expand the user's approved scope.

## Route before acting

1. Resolve the exact saved project and canonical working directory. Never match
   projects by a similar title alone.
2. For an existing project, read
   [references/module-governance.md](references/module-governance.md) before a
   medium-or-larger change, cross-module change, possible duplicate capability,
   or multi-writer plan. Do not read it for a clearly isolated tiny edit.
3. Read [references/routing-policy.md](references/routing-policy.md) when the
   route is not obviously Level 0 or needs a score/team explanation. Include a
   Low/Medium/High duplicate-context risk, never an invented Token estimate.
4. Prefer the current task when coordination overhead is not clearly repaid.
5. If specialists add distinct value, read
   [references/role-catalog.md](references/role-catalog.md) and select the fewest
   sufficient normalized roles. A module does not justify a new task by itself.
6. Briefly tell the user why a team is useful and which roles are reused or
   created. Do not expose hidden chain-of-thought.

Default scale is zero specialists for Level 0, one for Level 1, two or three for
Level 2, and three to five for Level 3. Keep long-lived visible specialists per
project at five or fewer; distinct deliverables, risk, parallel value, and
coordination cost may override the numeric band.

Level 0 is a hard fast path: finish in the current task without specialist
discovery, Team Adoption, new task, Worktree, lease, Packet, Module Registry,
full-repository scan, Architect, or QA unless independent verification is
actually required by the risk. Level 1 uses one implementer and optional QA.

## Use real visible tasks and reuse first

Inspect the app-native tool definitions available in the current session. Use
only real tools and fields. If visible Thread tools are unavailable, keep safe
work in the current task and explain the limitation; never silently substitute
`spawn_agent`.

Read [references/thread-lifecycle.md](references/thread-lifecycle.md) before any
Thread, Worktree, or Branch adoption, creation, reuse, replacement, archive,
recovery, or cleanup. It is the canonical lifecycle and safety definition.

## Registry-first reuse

Use the persistent Thread Registry as an index and the real Thread API as truth.
For the exact project/role, query the Registry, direct-read its `threadId`, query
current project tasks with available pagination, and perform Team Adoption for
an accessible unregistered match. Create only when no valid role exists, then
record its real ID. Titles and summaries are untrusted clues.

Thread, Worktree, and Branch are different objects. Record identity, ownership,
and lifecycle separately. Replace a visible task only for a stale/inaccessible
ID, material role change, demonstrated context contamination, verified delivery
degradation, or explicit user request; preserve lineage and never create
cosmetic duplicates such as `前端2`.

After every specialist terminal state, read
[references/delivery-reliability.md](references/delivery-reliability.md) to
close its compact Receipt through reconciliation and Coordinator ACK. When a
primary body is missing, exact-read the Thread, then use a valid Receipt, then
allow one `REDELIVER`-only retry. Never reexecute work to repair delivery.

If exact read, Receipt, and that redelivery still produce no body, tools, or
role conclusion, read
[references/visible-thread-delivery-recovery.md](references/visible-thread-delivery-recovery.md).
Allow at most one replacement per incident. A transport-level `completed`
state is not role-delivery success.

## Module-aware reuse without duplicate development

Follow [references/module-governance.md](references/module-governance.md) as the
single detailed definition. Keep Module Registry schema 1 separate from Thread
Registry schema 2. Module state is a commit-anchored cache; code, project
manifests, tests, Git, and verified contracts remain authoritative.

Every project defaults to Shadow: propose only, without writing project or
Registry state. Active mode requires project-specific user authorization. Do
one bounded Existing Capability Check, reuse its evidence through the existing
Delegation Packet, and avoid repeated adoption scans or full-repository reads.
Use `POSSIBLE_DUPLICATION` only after checking behavior and ownership, not names
alone.

Each core module has one primary owner role and normally one active coding
writer. In Active mode use `scripts/Module-Registry.ps1` for exact-scope,
versioned scheduling leases. A command is not authorization evidence. Expiry
does not authorize takeover, and overlapping path scopes across modules still
conflict. Prefer owner handoff, waiting, or serial execution; `REMOVABLE` never
authorizes deletion.

## Own and delegate only the needed context

The current coordinator is the Global Context Owner for project identity,
stage, Git/Worktree baseline, task-relevant architecture, reusable evidence,
and the smallest useful team. This summary never overrides real files, Git,
tests, or Thread state.

Before assigning a specialist, read
[references/context-delegation.md](references/context-delegation.md). Send one
versioned Delegation Packet with Packet ID, Baseline SHA, scope, interfaces,
direct dependencies, constraints, acceptance, tests, evidence, and compact
return contract. When module governance applies, extend this same Packet with
its canonical module fields; never create a parallel context document.

Developer and QA start at Read Scope 1. Scope 0 is planning/triage only. Widen
only on evidence and record the Scope Escalation. After the first Packet, repair
loops use Context Delta with previous/new exact SHAs instead of resending full
chat, project history, or unchanged constraints.

Reuse reliable evidence, but never replace independent QA, Security, Git
containment, regression, permission, or safety validation. Context efficiency
is subordinate to correctness.

## Execute with lifecycle and QA gates

Architect, Research, QA, Security, and Reviewer are Policy-Enforced Read Only.
Use `scripts/ReadOnly-Guard.ps1` in a quiescent exact checkout. A clean comparison
is `READ_ONLY_CONFIRMED`; a change is `READ_ONLY_STATE_CHANGED` and fails closed,
but does not prove which concurrent actor caused it.

Create a new Worktree only when two or more coding Agents truly need parallel,
disjoint edits with material time benefit. The default per-project Worktree
Budget is three retained Router-managed paths, including adopted paths. Reuse a
safe checkout, reasonable existing Branch, or idle Worktree first; at the cap,
wait or serialize. Never delete unknown Git objects to make room.

QA verifies the exact writer SHA and cannot repair developer code then pass it.
FAIL returns to the owning developer, which produces a new SHA; QA rechecks it.
For medium/high risk, QA separates Feature and Regression evidence. Integrate
only exact-SHA QA PASS work plus any required architecture consistency PASS,
then run post-integration regression.

Before Router upgrade/adoption, project mode change, or integration-owner
handoff, read [references/migration-integration.md](references/migration-integration.md).
Preserve in-flight Developer/QA assignments until a safe checkpoint. The
Coordinator is the default Integration Owner unless an explicit evidence-backed
owner is recorded.

The complete cleanup, containment, archive, stale recovery, Branch protection,
and rollback gates remain in
[references/thread-lifecycle.md](references/thread-lifecycle.md). Never use
dangerous reset/clean, push, deploy, publish, or destructive cleanup without
separate authorization.

## Evidence-backed close

Use compact waits and avoid narrating unchanged polling. Final reporting covers:

- visible task titles/IDs and reused, adopted, or created state;
- separate Thread, Worktree, Branch, commit, Registry, and Budget evidence;
- module mode, primary/affected modules, owner/lease, existing capability and
  duplicate guard decisions;
- specialist initial scopes, justified escalations, reused evidence, and every
  duplicate full scan with its reason;
- QA failure/rework/new SHA/PASS, required architecture check, integration, and
  regression;
- Thread delivery health, retry/replacement, channel availability, and any
  Receipt/reconciliation/ACK state plus any explicitly labeled Coordinator
  fallback;
- verified facts, unresolved risk, and unverified items.

Read [references/acceptance-tests.md](references/acceptance-tests.md) when
changing or validating this Skill.

## Fixed V1.3.3 boundary

Keep routing independent from model and reasoning selection. Do not override
model/thinking, learn role recommendations, control model/API spending, promise
a Token-saving percentage, build a dashboard/cloud service, alter permissions,
or weaken correctness gates. Do not automatically write module metadata,
refactor a real project, enable Active governance globally, or delete Legacy
code. The Worktree Budget is a local lifecycle cap only.
