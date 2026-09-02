# Auto Visible Team Router

Workstream-based engineering routing for Codex.

- **Version:** 2.0.0
- **Default mode after installation:** SHADOW
- **Canonical Skill name:** `auto-visible-team-router`

V2 routes work by observable deliverables, dependencies, write ownership,
parallel benefit, and evidence-triggered risk gates. It replaces V1.3.3's
long-lived project-role Thread model while retaining exact-SHA verification,
bounded context, one writer per scope, Worktree safety, and non-destructive Git
rules.

V2 is platform-adaptive: it decides the logical Workstream route first, then
selects an execution backend. A logical parallel route may safely run as a
serialized fallback when the platform cannot prove isolated parallel coding.

## What changes in V2

```text
Requirement
  -> deliverables
  -> dependency graph
  -> single-owner test
  -> parallel benefit gate
  -> LOCAL / SERIAL_1 / PARALLEL_2 / PARALLEL_3 / PLAN_FIRST
  -> CURRENT_THREAD / COLLAB_SUBAGENT / MANUAL_VISIBLE_WORKTREE
     / AUTO_VISIBLE_WORKTREE
  -> integration when needed
  -> evidence-triggered QA / Security / Architect / Reviewer gates
```

The primary unit is a short-lived **Workstream**:

```text
project + batch + workstream
```

A capability such as Fullstack, QA, Security, or Architect is metadata or a
gate. It is not a permanent employee identity and does not create a visible
task by itself.

## Project identity

V2 does not require `thread.projectId` for local repository work. It resolves
the first available stable identity:

1. `id:<projectId>`;
2. `git:<canonical-git-root>` with an exact HEAD;
3. `path:<canonical-path>` for an unambiguous non-Git local folder.

Git remotes are optional. Windows path keys are absolute, trailing-separator
normalized, and case-normalized for the filesystem contract. Display titles
and old permanent role names are never identity sources.

## Defaults

- Prefer `LOCAL` or `SERIAL_1`.
- Prefer `CURRENT_THREAD`; parallel execution is an optimization, not a
  correctness prerequisite.
- Every extra Agent must own a distinct, independently checkable deliverable.
- Multi-file or cross-layer work alone does not create Agents or QA.
- Maximum simultaneous coding Workstreams is 3; larger batches run in waves.
- One active writer owns each file or overlapping path scope.
- New Worktrees are for genuine parallel coding, not visual team structure.
- The Router-managed Worktree Budget defaults to 3.
- Telemetry defaults off.
- Token or credit savings are reported only from authoritative measurements;
  otherwise usage is `Unknown`.

## Execution backends

- `CURRENT_THREAD` is the default for LOCAL, SERIAL_1, and safe serialized
  fallback of logical PARALLEL_2/PARALLEL_3.
- `COLLAB_SUBAGENT` exists on the current tool surface, but collaboration
  Agents share one working tree and have no explicit cwd/Worktree parameter.
  Parallel coding is therefore forbidden; bounded read-only analysis may be
  used when independently valuable.
- `MANUAL_VISIBLE_WORKTREE` is optional and user-assisted. The Router returns
  `READY_FOR_MANUAL_VISIBLE_DISPATCH` and adopts only a real Thread whose
  Project identity and repository containment pass.
- `AUTO_VISIBLE_WORKTREE` is frozen as `UNSUPPORTED` with reason
  `THREAD_CREATION_PLATFORM_LIMITATION`. Production routing must not call it.

When a logical parallel route lacks a safe backend, V2 returns
`SERIALIZED_FALLBACK` or `SERIALIZED_WAVES` rather than blocking an ordinary
Feature. See `references/execution-backends.md` and
`references/platform-capability-history.md`.

## Modes

### SHADOW

The safe installation default. V2 may propose a bounded route, but it cannot
dispatch specialist Threads, edit product code, create Worktrees or Branches,
integrate changes, or write V2 runtime telemetry.

### CANARY

Enabled only for one exact `project_key + batch_id`. Every other project and
batch behaves as SHADOW. V1 and V2 must not both route the Canary.

### ACTIVE

Production V2 routing after offline validation, SHADOW installation,
platform-adapted synthetic validation, and promotion checks pass.

Ambiguous or conflicting router state fails closed with
`DUAL_ROUTER_BLOCKED`.

## Risk gates

Independent QA remains required for risks such as cancellation/concurrency,
credentials/auth/permissions, migration, critical persistence, release
candidates, high-impact defects, important shared contracts, repeated repair,
or multi-lane integration.

Security is required for credentials, trust boundaries, sensitive data,
permissions, encryption, or code-execution boundaries. QA and Security remain
read-only and cannot repair code and then pass their own repair.

## In-place upgrade from V1.3.3

This repository's management command intentionally performs an in-place
V1.3.3-to-V2 upgrade. It does not silently create a second production router.

Before installation:

1. record the clean V1 repository SHA and confirm it exists on the remote;
2. run the offline gate on the V2 branch;
3. identify the real installed Skill path and Codex home;
4. verify there is exactly one managed V1 AGENTS block.

Example:

```powershell
.\tests\Run-OfflineGate.ps1 -Root $PWD

.\scripts\Manage-Global.ps1 `
  -Action InstallShadow `
  -SourceRoot $PWD `
  -CodexHome 'C:\path\to\.codex' `
  -SkillRoot 'C:\path\to\skills\auto-visible-team-router'
```

`InstallShadow`:

- verifies and backs up the installed V1 Skill, AGENTS file, and runtime state;
- hashes the backup;
- archives V1 Thread/Module Registry state without converting it;
- installs V2 under the same canonical Skill identity;
- initializes a fresh Workstream Registry;
- replaces the V1 AGENTS block with exactly one V2 SHADOW block.

For an already-installed V2, use `UpdateV2Shadow` only from a clean export of
an exact Release Candidate SHA. It backs up the current V2 Skill, AGENTS block,
runtime state, and Registry; installs the allowlisted package; records the
source identity; initializes a fresh V2 Registry; and returns the runtime to
SHADOW before any ACTIVE promotion.

```powershell
.\tests\Run-ReleaseCandidateGate.ps1 -Root $PWD -ExpectedSha '<exact-sha>'

.\scripts\Manage-Global.ps1 `
  -Action UpdateV2Shadow `
  -SourceRoot 'C:\clean\candidate-export' `
  -SourceIdentity '<exact-sha>' `
  -CodexHome 'C:\path\to\.codex' `
  -SkillRoot 'C:\path\to\skills\auto-visible-team-router'
```

Use `Status` to inspect the installed path, mode, router block counts,
Registry presence, and legacy archives.

```powershell
.\scripts\Manage-Global.ps1 -Action Status
```

Promotion to CANARY or ACTIVE requires `-ConfirmSingleRouter`. Start a fresh
Codex task after global routing instructions change; an already-open task may
retain its earlier instruction chain.

## Offline validation

`tests/Run-OfflineGate.ps1` runs:

- PowerShell parser validation;
- PowerShell and Python static validators;
- JSON Schema instance validation;
- Project Identity priority and ambiguity fixtures;
- Repository/Worktree containment fixtures for primary, related, Codex-managed,
  unrelated, dirty, detached, lineage, and canonical ProjectKey behavior;
- route and backend-selection fixtures, including serialized fallback and
  four-deliverable wave scheduling;
- isolated Workstream Registry lifecycle tests;
- isolated install/AGENTS/backup/legacy-archive tests;
- failed-install rollback tests;
- ReadOnly Guard tests;
- `git diff --check`.

Offline success is reported only as:

```text
V2_OFFLINE_ENGINEERING_PASS
```

The platform-adapted synthetic gate never calls automatic visible Worktree
creation. Historical r1-r4 platform evidence is retained without being reused.

## Repository map

- `SKILL.md` — routing entry contract.
- `references/` — modes, Workstream routing, dependencies, context, risk,
  lifecycle, execution backends, platform capability history, Git safety,
  delivery, migration, and Canary rules.
- `scripts/Resolve-Route.ps1` — deterministic structured fixture helper.
- `scripts/Resolve-ExecutionBackend.ps1` — platform-adaptive backend selector.
- `scripts/Resolve-ProjectIdentity.ps1` — Project ID/Git/path identity resolver.
- `scripts/Resolve-RepositoryContainment.ps1` — Thread checkout/common-dir,
  worktree inventory, lineage, dirty-state, and ownership resolver.
- `scripts/Manage-Global.ps1` — backup, install, mode, and AGENTS lifecycle.
- `scripts/Workstream-Registry.ps1` — batch/workstream Registry lifecycle.
- `scripts/ReadOnly-Guard.ps1` — exact Git-state comparison for read-only gates.
- `schemas/` — V2 configuration, Project Identity, Repository Containment,
  route, and Registry schemas.
- `tests/` — offline validation and lifecycle fixtures.

## Boundaries

The Router does not push, deploy, publish, spend money, use real credentials,
weaken security, delete unknown Git objects, promise a fixed Token-saving
percentage, or auto-enable itself globally.

## License

MIT. See [LICENSE](LICENSE).
