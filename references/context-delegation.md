# Workstream context delegation

## Batch Context Owner

The current Coordinator assembles the one task-relevant batch snapshot.

Real files, Git, tests, contracts, and app-native Thread state remain
authoritative.

## Workstream Packet

Send one initial Packet:

```yaml
packet_id:
packet_version: 1
batch_id:
workstream_id:
project_key:
objective:
baseline_sha:
branch_worktree:
owned_scope:
forbidden_scope:
read_start_points:
relevant_contracts:
dependencies:
existing_capability_evidence:
known_constraints:
acceptance_criteria:
required_tests:
risk_flags:
return_contract:
```

Do not attach by default:
- complete conversation history;
- all historical milestones;
- every architecture document;
- unrelated old bugs;
- exhaustive file list;
- other lanes' complete transcripts/logs.

## Read Scope Ladder

- Scope 0 — Packet / planning only.
- Scope 1 — assigned files, exact diff/SHA, direct dependencies, assigned tests.
- Scope 2 — local module/package/component.
- Scope 3 — participating cross-module call/data flow.
- Scope 4 — repository-wide.

Coding owners start at Scope 1.

Scope 4 requires evidence such as:
- unresolved defect location after local reads;
- global architecture decision;
- large migration;
- broad Security audit;
- dependency ambiguity local reads cannot resolve.

"Become familiar with the repository" is not sufficient.

## Scope escalation

```yaml
scope_escalation:
  from:
  to:
  reason:
  evidence:
```

## Context Delta

After initial Packet, repairs/rechecks receive only changed information:

```yaml
context_delta:
  packet_id:
  packet_version:
  previous_sha:
  new_sha:
  changed_files:
  changed_diff_or_ref:
  new_findings:
  new_test_results:
  unchanged_contract_ref:
```

If ownership, baseline, contract, permissions, acceptance, or milestone changes
materially, increment the Packet version.

## CURRENT_THREAD serial switching

When one current task executes several Workstreams, keep their logical
identities separate:

1. activate one Workstream Packet;
2. write only inside that Workstream's owned scope;
3. produce a compact terminal checkpoint;
4. close or suspend its write ownership;
5. activate the next Packet;
6. use Context Delta for repairs instead of reopening all prior context.

Do not combine two Workstream ownership scopes into one undifferentiated step.

## Other-lane information

A Workstream receives another lane's output only when it is a direct dependency
or integration contract.

Do not broadcast every lane's transcript to every other lane.

## Return contracts

Coding Workstream:

```yaml
status: PASS | FAIL | BLOCKED
workstream_id:
commit_sha:
worktree:
branch:
changed:
tests:
scope_escalation:
new_contracts:
blockers:
```

Read-only gate:

```yaml
status: PASS | FAIL | BLOCKED
gate:
verified_sha_or_candidate:
checks:
findings:
scope_escalation:
read_only_guard:
```

Return new evidence and decisions, not repeated project narration.
