# Module governance V1.3.1

Read this reference for an existing project when a requested change is medium or
larger, may cross module boundaries, may duplicate an existing capability, or
needs more than one coding writer. Do not read it for ordinary conversation or
a clearly isolated tiny edit.

## Contents

- Purpose, truth order, and separate Registry
- Shadow adoption and bounded discovery
- Existing capability and duplicate implementation checks
- Ownership, write leases, and Delegation Packet impact
- Architect, legacy, QA, and integration gates

## Purpose and fixed boundary

Use modules to locate responsibility before choosing people or writing code.
A module is a responsibility boundary in the product; a visible Thread is a
reusable work context. One Thread may own several related modules, and a module
does not justify a new Thread by itself.

Module governance changes routing only. It does not grant permission to edit a
project, refactor existing code, delete legacy code, create a Branch or
Worktree, or bypass the existing lifecycle and QA gates.

## Truth order and separate Registry

Use this evidence order:

1. current source, project configuration, tests, and Git state;
2. an explicitly maintained project architecture or module manifest;
3. the Router Module Registry as a cached index;
4. existing task summaries and names as untrusted discovery clues.

Keep Module Registry schema 1 separate from Thread Registry schema 2. The
default path is
`$CODEX_HOME/auto-visible-team-router/module-registry.json`. Never add module
objects or volatile write leases to `thread-registry.json`.

Every confirmed module record includes project identity, module ID/name,
responsibilities, relevant paths, owner role, current owner Thread when one is
assigned, dependencies, dependents, lifecycle state, evidence sources,
confidence, `verifiedAt`, and `verifiedAgainstCommit`. A record without a
current commit anchor is stale guidance, not proof of the current architecture.

Use `scripts/Module-Registry.ps1` only after the user authorizes persistent
module governance for the exact project. In Shadow mode, produce a proposed
map in the current response or an authorized report; do not create or update
the Registry and do not write project metadata.

## Shadow adoption and bounded discovery

Module governance defaults to `Shadow` for every project. On first adoption:

1. resolve the exact project and Baseline SHA;
2. inspect top-level manifests, relevant architecture guidance, entry points,
   package/namespace boundaries, and current task evidence;
3. follow references and Git history only where they resolve an uncertain
   responsibility;
4. propose a Project Module Map with `Confirmed`, `Inferred`, or `Unknown`
   confidence;
5. leave uncertain ownership as `Unknown`; never infer responsibility from a
   directory name alone.

This first adoption may justify Scope 2-4. Record the reason. Normal feature
work must not repeat the adoption scan. Start from the confirmed module map,
assigned files, current diff/tests, affected contracts, and direct dependencies
at Scope 1; widen only on evidence and record the Scope Escalation.

Enable `Active` mode for a project only after its proposed map and owner
boundaries have been reviewed and the user authorizes persistent state. Enabling
one project does not enable another project with a similar name.

The Active record must include `AuthorizedAt`, human-readable authorization
evidence, the exact resolved project key, previous/new mode, and either a
verified baseline commit or architecture-map evidence. The mode-setting command
is not authorization proof. Active-to-Shadow is blocked while an Active
lease remains; reach a verified safe checkpoint first.

A `Confirmed` module record requires ID, name, non-empty responsibilities and
paths, owner role, known lifecycle state, sources, `verifiedAt`, and
`verifiedAgainstCommit`. `dependencies` and `dependents` must exist even when
empty. Unknown ownership stays Inferred/Unknown or uses owner role `Unknown`;
do not fill authoritative fields by guessing.

## Existing Capability Check

Before a medium-or-larger change, answer with evidence:

- What requested behavior already exists, and where?
- Which service, state owner, data model, API, UI flow, configuration, tool,
  cancellation path, or tests already implement part of it?
- Is the candidate authoritative, an adapter/provider/compatibility layer, or
  a legacy implementation?
- Can the requested behavior safely extend the existing owner?

Start from the primary module and direct dependencies. Repository-wide search
is allowed only when the map is missing/stale, the owner is unresolved, a call
path escapes the module, or concrete duplicate/regression evidence requires it.
Reuse the findings in the Delegation Packet; do not ask each role to repeat the
same search.

Refresh an Existing Capability Check only when its baseline is stale, a changed
interface/module boundary invalidates it, new runtime/test evidence conflicts
with it, the owner becomes unresolved, or the requested behavior escapes the
verified scope. Record `CapabilityCheckRefresh`, the reason, and old/new
evidence. A refresh is bounded; it does not justify an unrelated full scan.

Prefer extension of the authoritative implementation. A replacement needs an
Architect decision or an equivalently explicit coordinator decision for a
bounded local change, plus migration, cutover, compatibility, and rollback
conditions.

## Duplicate Implementation Guard

Run a bounded guard before implementation and against the exact proposed diff
before integration. Similar names, services, managers, handlers, schemas,
state machines, routes, configurations, tools, or UI flows are signals, not
proof.

Inspect callers, contracts, behavior, data ownership, lifecycle, and migration
intent. Adapters, providers, strategies, platform implementations, test doubles,
and compatibility layers may legitimately share an interface shape.

When evidence is unresolved, report `POSSIBLE_DUPLICATION` with both locations,
the overlap, the evidence still needed, and the responsible decision owner.
Never auto-merge, auto-delete, or silently preserve two authoritative
implementations.

## Ownership and write lease

Each confirmed core module has one primary owner role. The owner role is the
architectural responsibility; `ownerThreadId` is only the current assignment.
Reuse/adopt a suitable visible Thread before creating one. A stale or blocked
owner Thread may be reassigned by the Coordinator after real task verification
and an audited Registry update.

In Active mode, one module normally has one active coding writer. Record a
Router scheduling lease with module ID, writer Thread ID, task and Packet ID,
Packet version,
Worktree, Branch/detached state, allowed paths, Baseline SHA, acquisition,
last-verification and expiry times, state, and release reason.

Lease acquisition is idempotent only when module, writer, task/Packet,
Packet version, Worktree, Branch/detached state, Base Commit, and normalized
allowed paths all match exactly. A changed scope or baseline is a different
request: stop at a checkpoint, then refresh/release and acquire a new lease.

Compare `allowedPaths` against every Active lease in the project, not only the
same module. Exact paths, parent/child directories, and shared files conflict.
One file/interface/range has one writer by default. Resolve overlap by handoff,
waiting, serialization, or a named Integration Owner; module labels do not make
overlapping filesystem scopes safe.

The lease is not an operating-system lock. Before treating it as active,
stale, or released, verify the real Thread, Worktree, Branch, Git status, and
current assignment. Expiry makes a lease an unverified stale candidate; it
does not authorize takeover. Mark it stale only with recorded verification
evidence. Never delete or reset a Git object to clear a lease.

Module updates are patches: unspecified authoritative fields remain unchanged.
Do not rebuild a whole module record from command defaults. Before replacing a
Registry file, retain only a parsed previous known-good `.bak`; report unknown
corruption and fail closed instead of automatically restoring it.

When two writers need the same module, prefer handing the change to its owner,
waiting, or serial execution. Parallel work inside one module requires an
explicit architecture split with disjoint files/contracts and must still obey
the Worktree Budget. Shared cross-cutting files have one integration owner.

## Change Impact in the existing Packet

Do not create a second long change document. Use the exact module and impact
fields defined in [context-delegation.md](context-delegation.md) inside the
existing Delegation Packet. Pass that Packet once. Later Developer/QA repairs
use the existing Context Delta unless the module boundary, owner, baseline,
scope, contract, or acceptance criteria changed materially.

## Architect and cross-module gates

Use Architect for a new or changed contract, uncertain responsibility boundary,
shared state/data/permission/concurrency, major migration/refactor, public
infrastructure, unresolved authoritative duplication, or conflicting module
owners. Crossing two modules with stable contracts is not sufficient by itself.
A repeated QA failure adds Architect only when the evidence is architectural.

Define one source of truth for shared behavior. For example, Voice may emit a
stop intent, Session may own cancellation, and AI may observe the cancellation;
do not let every layer create its own cancellation mechanism.

## Legacy and integration safety

Use `ACTIVE`, `MIGRATING`, `LEGACY`, `REMOVABLE`, or `UNKNOWN`. `REMOVABLE`
means only that stated migration and containment conditions appear satisfied.
It never authorizes code, file, schema, Branch, or Worktree deletion. Deletion
still needs exact verification and authorization.

For a medium/high-risk change, QA distinguishes Feature tests from Regression
tests and verifies the exact SHA. Before integration, the integration owner
checks duplicate implementation evidence, ownership/contract consistency,
dependency direction, temporary compatibility code, legacy cutover state, and
the current architecture gate. Integration requires exact-SHA QA PASS plus all
required architecture checks; post-integration regression still applies.

When changing existing behavior, first locate the current contract and tests.
Add a minimal regression test when it is within the authorized task and is the
smallest reliable protection. If no reliable protection can be added, record
the uncovered risk instead of claiming the old behavior is protected.

Update a confirmed module record only after an important responsibility,
contract, path, dependency, owner, or lifecycle change. Do not update it for
every small edit, and never treat the cached map as fresher than the commit it
was verified against.
