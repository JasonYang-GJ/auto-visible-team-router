# Context-efficient delegation retained in V1.3.3

Read this reference only after routing selects at least one visible specialist.
It narrows repeated context loading without narrowing the correctness standard.
Context efficiency is subordinate to correctness.

## Global Context Owner

The current coordinator owns context assembly and routing. It should establish:

- exact project identity and current stage or milestone;
- current Branch, Worktree, and Baseline SHA;
- the task-relevant architecture and known constraints;
- reliable evidence already produced by another role;
- distinct role deliverables and the smallest useful team.

This role does not make its summary authoritative. Specialists must verify the
real files, Git state, interfaces, tests, and Thread state needed for their own
deliverable.

## Delegation Packet

Send one complete Packet at the first assignment:

```yaml
packet_id: stable task-local identifier
packet_version: 1
project: exact project ID, name, and canonical root
role: normalized role
objective: one bounded outcome
current_baseline: exact SHA plus Branch/Worktree state
stage_milestone: relevant stage only
allowed_scope: files, modules, actions, and write ownership
forbidden_scope: explicit exclusions and side effects
primary_files_modules: expected starting points
primary_module: confirmed module ID or Unknown when module governance applies
affected_modules: changed and behaviorally affected module IDs
module_owner: owner role plus current Thread ID when assigned
relevant_interfaces_contracts: verified contracts or locations to verify
dependencies: direct dependencies and owner boundaries
existing_capability_evidence: authoritative candidates, locations, tests, and conclusion
change_impact: affected behavior, data, API, UI, permissions, and regression risk
architecture_gate: Required or NotRequired plus evidence-based reason
module_write_lease: verified lease ID or NotRequired
known_constraints: safety, compatibility, UX, and authorization constraints
acceptance_criteria: observable pass conditions
required_tests: exact checks or justified test class
required_evidence: SHA, diff, output, screenshots, or review records
return_format: role-specific compact contract
```

Use a new `packet_version` when baseline, scope, interfaces, constraints, or
acceptance criteria materially change. A Packet is a bounded index and working
contract, not permission to trust unverified claims.

Do not attach complete chat history, every stage or architecture document,
unrelated old bugs, or an exhaustive file list by default.

The module fields extend this Packet; they do not create a second planning
document. Read [module-governance.md](module-governance.md) only when its trigger
applies. Reuse the Coordinator's capability evidence, but independently verify
the exact code, SHA, contract, and tests required by the assigned role.

## Read Scope Ladder

- **Scope 0 — Packet Only:** planning, triage, or deciding the next read. It is
  not sufficient by itself for a code edit, exact-SHA QA acceptance, Security
  sign-off, or Git containment proof.
- **Scope 1 — Assigned Evidence:** assigned files/interfaces/tests, the relevant
  diff or SHA, changed files, and direct dependencies. This is the default
  starting scope for Developer and QA.
- **Scope 2 — Local Module:** the surrounding package, namespace, component, or
  directly related local data flow.
- **Scope 3 — Cross-Module:** the participating call chain or data flow across
  modules.
- **Scope 4 — Repository-Wide:** only for global architecture, unresolved defect
  location, dependency ambiguity that local reads cannot resolve, broad Security
  audit, large migration, or a demonstrably insufficient Packet.

Escalate scope when compile/type/reference evidence, a failing test, an unknown
interface owner, an unresolved call path, or a discovered regression risk points
outside the current boundary. Record:

```yaml
scope_escalation:
  from: 1
  to: 3
  reason: concrete evidence requiring the wider read
```

Ordinary authorized reads do not need a new user approval. Existing filesystem,
network, privacy, and authorization boundaries still apply.

## Role-specific starting points

- **Developer:** Packet + assigned files + direct dependencies. Expand on
  evidence; never scan the repository merely to become familiar with it.
- **QA:** exact Developer SHA, diff, changed files, acceptance criteria,
  relevant tests, and directly affected interfaces. QA remains independent and
  does not trust the Developer self-report.
- **Architect:** start with the affected boundary and local modules for a local
  interface, bridge, or refactor. Broader reads are allowed when the architecture
  decision is genuinely system-wide.
- **Security/Reviewer:** read the evidence and attack surface required by the
  assigned review scope. Do not claim comprehensive coverage beyond that scope.
- **Research:** answer the coordinator's bounded question and return sources,
  uncertainty, and decision impact without re-analyzing the whole project.

## Context Delta

After the initial Packet, send only changed task context unless the Packet itself
changed. Every Delta includes:

```yaml
packet_id: existing Packet ID
packet_version: existing or incremented version
previous_sha: exact previously reviewed SHA
new_sha: exact replacement SHA when one exists
changed_files: delta file list
delta_diff: changed diff or precise reference
new_findings: QA failures, resolved findings, or blockers
new_test_results: checks added or rerun
unchanged_constraints: reference to still-active scope and acceptance criteria
```

A QA FAIL returns findings and the current exact SHA to the original developer.
The repair returns a new SHA and delta evidence. QA rechecks that SHA. If scope,
baseline, interfaces, or acceptance criteria changed materially, increment the
Packet version instead of pretending the old contract still applies.

### Packet invalidation events

Issue a new Packet version when the baseline/integration baseline, Branch,
Worktree, stage, module owner or boundary, interface, permissions, data
ownership, Integration Owner, or capability evidence changes materially. A
pure QA repair with unchanged scope, contract, ownership, and acceptance remains
a Context Delta. Boundary changes are never hidden inside a same-version Delta.

When a prior capability check becomes stale, return only its refresh reason and
old/new evidence as `CapabilityCheckRefresh`; do not resend the original scan or
start an unjustified repository-wide scan.

## Compact Return Contract

Use the Packet's stable `packet_id` as the Delivery Receipt `TaskId` unless the
assignment already has a stronger exact task identifier. Before the final body,
record the compact result in the existing Thread Registry and close it through
[delivery-reliability.md](delivery-reliability.md). The Receipt is the same
return data in compact metadata form, not a second Packet or a chat transcript.

Developer:

```yaml
status: PASS | FAIL | BLOCKED
commit: exact SHA
worktree: absolute path
branch: name or detached
changed: files and behavior
tests: commands and results
scope_escalation: none or from/to/reason
blockers: remaining blockers
```

QA:

```yaml
status: PASS | FAIL | BLOCKED
verified_sha: exact SHA
checks: evidence checked
failures: actionable findings
regression: results and uncovered risk
read_only_guard: result
scope_escalation: none or from/to/reason
```

Architect returns `status`, `decision`, `affected_interfaces`, `risks`,
`required_changes`, and `scope_escalation`. Other roles use the same principle:
return new decisions and evidence, not a repeated project narrative.

## Duplicate work and parallelism

Pass reliable existing analysis with its evidence instead of ordering a fresh
full scan. Independent verification remains mandatory where required.

Classify duplicate-context risk as Low, Medium, or High. Use it to decide
whether another role or parallel lane has enough distinct value. Allow real
parallel work when two or more coding writers have disjoint ownership and the
time benefit is material. When several roles would reread the same large area
for little independent value, reduce the team or serialize. Never create a
token calculator or report an unmeasured savings percentage.

## Existing Thread hygiene and correctness

Reuse an accessible exact-project role Thread, but begin a new assignment with
the current Packet instead of restating its whole history. Apply the existing
context-contamination replacement rule only for demonstrated project pollution,
persistent obsolete assumptions, or an inability to separate the old and new
stage. Do not replace a Thread merely to claim context savings.

If a bounded read is insufficient, widen it. Do not skip tests, QA, Security,
Git checks, dependency reads, or safety validation; guess interfaces or project
state; hide blockers; or reduce acceptance criteria for context efficiency.
