# Complexity and routing policy

Use this policy after the applicability gate. Ordinary chat and non-project
explanations are excluded before scoring.

## Transparent score

Score each item once, cap each group, and record only a short reason.

### Scope: 0-25

- Files likely touched: 0 for none/read-only, 3 for 1, 7 for 2-4, 12 for 5+.
- Modules/components: 0 for one, 4 for two, 8 for three or more.
- Expected dependent steps: 0 for 1-3, 3 for 4-6, 5 for 7+.

### Technical breadth: 0-20

- Distinct domains beyond the first: 4 each, maximum 12. Domains include UI,
  backend/API, database, mobile, Windows/system integration, AI, deployment,
  and security.
- Operating-system or privileged system API: 4.
- External service, protocol, or network integration: 4.

### Architecture and data: 0-20

- New boundary, major architecture change, or large refactor: 8.
- Database/schema/data migration: 7.
- Cross-service or public-interface contract: 5.

### Risk and blast radius: 0-25

- Authentication, authorization, permissions, privacy, secrets, or security: 8.
- Irreversible change, production release, or consequential migration: 7.
- Critical user/business flow or high-impact defect: 5.
- Concurrency, consistency, state synchronization, or recovery: 5.

### Uncertainty: 0-10

- Materially ambiguous requirements: 4.
- Research or unfamiliar technology needed: 3.
- Several reasonable designs require a tradeoff: 3.

`complexity_score` is the sum, clamped to 0-100.

## Numeric bands

- 0-14: Level 0.
- 15-34: Level 1.
- 35-59: Level 2.
- 60-100: Level 3.

Do not use the band mechanically. A contained task with a high file count can
route down when one owner is faster and safer. Security, irreversible data
change, a true architecture decision, or several independently valuable lanes
can route up. Coordination overhead can route down. State the override reason.

## Context and duplicate-read cost

Classify `duplicate_context_risk` without estimating tokens:

- **Low:** roles have distinct evidence or modules and little shared rereading.
- **Medium:** some shared background is needed, but a bounded Packet and local
  scopes keep most work distinct.
- **High:** several roles would independently scan or reconstruct the same large
  project area while producing little distinct value.

Use this factor to reduce an unnecessary Architect/Reviewer, choose an initial
Read Scope, or serialize low-value overlapping lanes. It may not remove a
required QA, Security, Git containment, regression, or safety check. Real
parallel writers with disjoint ownership remain allowed when the time benefit
is material.

## Structured route decision

Keep this internally concise and show the user only the useful summary.

```yaml
route_decision:
  applicable: true
  complexity_score: 47
  level: 2
  reasons:
    - three modules and a user-facing data flow
    - independent API and UI implementation
  selected_roles: [Frontend, Backend, QA]
  existing_roles: [Frontend]
  create_roles: [Backend, QA]
  duplicate_context_risk: Medium
  initial_read_scopes:
    Backend: 1
    QA: 1
  visible_specialist_cap: 5
  model_route: null
  reasoning_route: null
```

For Level 0, set `selected_roles`, `existing_roles`, and `create_roles` to empty.
For excluded conversation, set `applicable: false` and do not score.

### Hard fast paths

- **Level 0:** stay in the current task. Do not discover/adopt/create specialist
  tasks, create Worktrees or leases, issue a Delegation Packet, write either
  Registry, run a full-repository scan, or add Architect/QA unless the actual
  risk independently requires verification. Use only proportionate local tests.
- **Level 1:** use at most one implementation owner and optional independent QA.
  Reuse a generic Developer before creating a narrower specialist when its
  established scope already fits.

## Selection checks

- A score does not create a role; each role must have a distinct deliverable.
- Prefer Fullstack over separate Frontend and Backend when one editor can safely
  own the small vertical slice.
- Add QA only under the independent-verification gates in the Role Catalog.
- Add Architect only under the architecture gates in the Role Catalog.
- Resolve the primary/affected modules and reuse a suitable owner role before
  creating another specialist. Module count does not equal role count.
- Parallelism is a benefit test, not a goal.
- Treat duplicate-context risk as a coordination-cost input, never as a reason
  to weaken correctness or claim unmeasured token savings.
- Reuse one bounded Existing Capability Check through the Delegation Packet.
  Do not make every selected role repeat project adoption or a repository-wide
  scan.
- Reassess after repeated failure, QA rejection, or newly discovered risk.
