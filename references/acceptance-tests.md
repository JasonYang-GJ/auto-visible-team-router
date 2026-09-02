# V2 acceptance tests

The package is acceptable for Shadow installation only when all static/offline
checks pass.

## A. Mode safety

1. Missing runtime state defaults to SHADOW.
2. SHADOW cannot create/adopt visible specialist Threads.
3. SHADOW cannot create Worktrees/Branches.
4. SHADOW cannot edit product code.
5. CANARY requires exact project + batch.
6. CANARY/ACTIVE with V1 routing ambiguity returns DUAL_ROUTER_BLOCKED.

## B. Routing

7. Tiny low-risk one-file change -> LOCAL.
8. Eight-file contained vertical slice may still -> LOCAL/SERIAL_1.
9. File/module count does not create Agents.
10. Every extra Agent maps to a distinct deliverable.
11. Maximum default coding lanes = 3.
12. Unstable shared contract -> PLAN_FIRST/SERIAL.
13. Overlapping writer scope -> SERIAL/BLOCKED.
14. No material parallel benefit -> SERIAL.

## C. Thread/context

15. Primary Thread identity is project + batch + workstream.
16. V2 does not search/reuse permanent Developer/QA role Threads.
17. Repair in same workstream may reuse same Thread.
18. New batch defaults to fresh workstream context.
19. Coding owner starts at Read Scope 1.
20. Repo-wide scan requires evidence.
21. Context Delta is used for bounded repair.

## D. Gates

22. Multi-file alone does not require QA.
23. Concurrency/cancellation triggers QA.
24. Credential/auth/permission change triggers QA + Security.
25. New shared contract across lanes triggers Architect or PLAN_FIRST.
26. Multi-lane integration normally triggers post-integration QA.
27. QA cannot repair and self-pass.

## E. Git

28. One writer per scope.
29. One coding lane does not justify a new Worktree.
30. Parallel writers require disjoint ownership.
31. Worktree Budget default = 3.
32. Unknown/adopted/user Git objects are never deleted for capacity.

## F. V1 coexistence

33. V2 state paths are separate from V1.
34. Shadow install preserves a readable, hashed V1 backup and archived Registry
    state; it never rewrites V1 role entries as V2 Workstreams.
35. Real Canary requires a single active router.
36. Rollback returns V2 to SHADOW/DISABLED and re-enables V1; V1 is not deleted.

## G. Usage claims

37. No fixed Token-savings percentage is promised.
38. Usage is recorded only from authoritative Codex measurements.

## H. Installation and rollback

39. The real installed Skill path is explicit or safely resolved; V2 is not
    installed into a second active directory.
40. InstallShadow requires exactly one V1 managed AGENTS block and no V2 block.
41. Unrelated AGENTS content is preserved while V1 is replaced by exactly one
    V2 SHADOW block.
42. The installed Skill, AGENTS file, runtime state, and V1 registries are
    copied into a timestamped backup with verified SHA-256 entries.
43. Active V1 Thread/Module Registry files move to a legacy archive and a fresh
    empty V2 Workstream Registry is created.
44. A failed post-swap installation restores the V1 Skill, AGENTS block, and
    Registry state and leaves no active V2 state/Registry.
45. V2 source installation uses an explicit allowlist and does not copy Git
    metadata or unrelated repository assets into the Skill root.

## I. Offline gate

46. Every PowerShell source/test file parses without syntax errors.
47. Representative route and Registry instances validate against the shipped
    JSON Schemas, including four deliverables with a three-lane wave cap.
48. Management and Registry lifecycle tests run only against isolated temporary
    Codex homes.
49. ReadOnly Guard confirms an unchanged repository and detects a synthetic
    state change.
50. The final offline gate includes `git diff --check` and emits
    `V2_OFFLINE_ENGINEERING_PASS` only when every preceding check passes.

## J. Project identity

51. Project ID plus Git repository -> `id:<projectId>`.
52. Missing Project ID plus canonical Git root -> `git:<canonical-root>`.
53. A Git repository without a remote remains valid.
54. Missing Project ID and non-Git canonical folder -> `path:<canonical-path>`.
55. Missing/ambiguous all identity sources -> `PROJECT_IDENTITY_BLOCKED`.
56. Equal display titles with different canonical paths produce different keys.
57. An old V1 permanent-role Thread is not adopted into a new V2 Workstream.

## K. Repository containment

58. Thread Git root equals canonical Git root -> PRIMARY_CHECKOUT PASS.
59. Different path with equal common-dir and inventory match -> RELATED_GIT_WORKTREE PASS.
60. A related checkout under Codex worktrees -> CODEX_MANAGED_WORKTREE PASS without claiming Router creation.
61. A real related Worktree named with `-2` passes; suffix is irrelevant.
62. Similar name and equal HEAD with a different common-dir -> UNRELATED_CHECKOUT BLOCKED.
63. Equal remote URL does not turn an independent clone into a Worktree.
64. Unattributed dirty state -> BLOCKED without cleanup.
65. Valid detached Worktree at explained baseline -> PASS.
66. Unexplained starting SHA mismatch -> BASELINE_LINEAGE_UNEXPLAINED.
67. A physically different related Worktree retains the canonical ProjectKey.

## L. Platform capability and execution backend

68. Logical Route and Execution Backend are independently represented.
69. LOCAL selects CURRENT_THREAD with zero extra Agent.
70. SERIAL_1 selects CURRENT_THREAD unless a capability-safe one-Agent backend
    has distinct value.
71. Logical PARALLEL_2 with no safe parallel backend returns
    SERIALIZED_FALLBACK and remains a valid ordinary Feature plan.
72. Logical PARALLEL_3 with no safe backend executes serialized waves.
73. True-concurrency correctness requirements block when no safe parallel
    backend exists.
74. Current COLLAB_SUBAGENT capability is available for independent context,
    stable Agent ID, result reading, and bounded packets.
75. Current COLLAB_SUBAGENT has no explicit cwd, Worktree, or independent
    checkout; parallel coding is FORBIDDEN.
76. AUTO_VISIBLE_WORKTREE is UNSUPPORTED with reason
    THREAD_CREATION_PLATFORM_LIMITATION.
77. Production route/backend resolution never selects or calls automatic
    visible Worktree creation while unsupported.
78. An explicit user request for visible parallel work returns
    READY_FOR_MANUAL_VISIBLE_DISPATCH.
79. Manual visible adoption requires a real Thread ID and Repository
    Containment PASS.
80. Visible backend unavailability does not block an ordinary Feature.

## M. Platform-adapted synthetic gate

81. CURRENT_THREAD Workstreams retain project + batch + workstream logical
    identity.
82. Serial Workstream switching uses a bounded Packet and compact checkpoint.
83. Context Delta remains the repair/update contract.
84. Credential/auth/permission scenarios still require QA + Security.
85. Multi-workstream integration still triggers risk-based post-integration QA.
86. Unknown/historical Worktrees are preserved and never adopted or deleted.
87. r1-r4 remain Platform Capability History, not reusable execution evidence.
88. The adapted synthetic test emits V2_PLATFORM_ADAPTED_SYNTHETIC_PASS.
89. The complete gate emits both V2_PLATFORM_ADAPTATION_PASS and
    V2_OFFLINE_ENGINEERING_PASS.

## N. Release Candidate and exact installation

90. Release Candidate validation requires an exact HEAD SHA and a clean working
    tree before and after the full offline gate.
91. A V2-to-V2 update accepts only V2.0.0 source with an exact source identity.
92. The current installed V2 Skill, AGENTS block, runtime state, and Registry
    are backed up before replacement.
93. Exact update preserves the original V1 rollback backup and legacy archive.
94. Exact update installs from an allowlisted clean source export, records the
    source identity, resets mode to SHADOW, disables telemetry, and initializes
    a fresh V2 Workstream Registry.
95. ACTIVE promotion occurs only after exact source/install hash equality and a
    fresh-session verification.
