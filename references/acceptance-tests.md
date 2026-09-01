# V1.3.3 mandatory acceptance matrix

Static fixtures never replace real visible-task, worktree, commit, QA, archive,
and direct-read evidence when the current Codex App exposes those capabilities.

1. Official Skill validator passes.
2. V1.2.0 static validator passes with all V1.1.1 invariants, required files,
   and no model/thinking routing.
3. First isolated Install succeeds and records a recoverable backup.
4. Repeated Install stays idempotent: one begin/end marker and unchanged AGENTS
   hash.
5. Disable removes only the managed block and retains Skill files/Registry.
6. Enable restores exactly one current V1.3.3 managed block.
7. Uninstall requires explicit confirmation, removes only the exact Skill root,
   retains Registry, and leaves a backup.
8. Unrelated pre-existing AGENTS bytes are preserved through the full lifecycle.
9. Registry persists project ID/name/path, normalized role, and separate Thread,
   Worktree, Branch, and delivery objects.
10. Registry blocks two Active entries for the same exact project/role.
11. A fresh PowerShell/Codex session recovers an existing Registry entry.
12. A Registry with more than 50 entries retrieves and direct-reads a target
    beyond position 50 without creating a duplicate.
13. A missing/inaccessible registered ID is marked Stale and replaced once,
    with lineage preserved.
14. Archive updates the real task and Registry state while preserving ID,
    purpose, time, and result.
15. A new safe Git repository has a real initial commit and no remote.
16. Frontend and Backend writers run in different real physical worktrees and
    different branches.
17. Frontend changes only `frontend.txt`, commits, and returns its SHA.
18. Backend changes only `backend.txt`, commits, and returns its SHA.
19. QA checks the exact first writer SHAs and returns an intentional FAIL for
    the missing frontend gate without editing developer code.
20. The owning Frontend role repairs the failure and produces a new SHA.
21. QA checks the replacement Frontend SHA plus Backend SHA and returns PASS.
22. The integration owner safely combines only QA-approved SHAs and the
    post-integration regression passes.
23. Architect/QA/Reviewer/Research guard reports clean before/after state as
    `READ_ONLY_CONFIRMED`; a synthetic edit is detected as
    `READ_ONLY_STATE_CHANGED` without unsupported role attribution.
24. Routing fixtures cover tiny edit (Level 0), one specialty, cross-layer,
    complex Windows AI, reuse, failure escalation, and ordinary explanation.
25. No project exceeds five active long-lived specialist roles; test tasks are
    archived after evidence capture.
26. Schema 1 Registry data migrates to schema 2 without losing identity and
    without assigning cleanup ownership to unknown legacy Git objects.
27. Team Adoption direct-reads and registers existing Developer and QA Threads
    without creating replacements; adopted Git objects are marked pre-existing.
28. Existing reasonable development Branches are considered before any new
    Branch, and the same Branch is never checked out in two Worktrees.
29. A new Worktree is allowed only for two or more true parallel coding writers;
    Architect, QA, Reviewer, Research, and Security create none by default.
30. Per-project Worktree Budget defaults to 3 and counts adopted plus
    Router-created retained paths; at Budget the order is reuse, wait, serialize.
31. A Router-created temporary Worktree is rejected unless Thread ID, Branch or
    detached state, path, Base Commit, CreatedAt, and lifecycle state are stored.
32. Worktree retirement is blocked unless status is clean, SHA recorded, QA is
    PASS, integration/retention is proven, and Router creation ownership matches.
33. User-created, adopted, unknown, dirty, unmerged, and protected Branches or
    Worktrees are never auto-deleted.
34. A Router-created local temporary Branch is cleanup-eligible only after its
    exact Commit is proven contained in the target and it is not checked out.
35. Near the configured Codex worktree limit, or when that limit cannot be
    verified safely, creation fails closed and never deletes unknown old paths.
36. The Coordinator is Global Context Owner for context assembly, but real
    files, Git, tests, and Thread APIs remain authoritative.
37. The first specialist assignment uses a Delegation Packet with stable Packet
    ID, Packet version, Baseline SHA, exact scope, acceptance, tests, evidence,
    and compact return contract.
38. Scope 0 is limited to planning/triage and cannot by itself authorize a code
    edit, QA PASS, Security sign-off, or Git containment result.
39. Developer and QA start at Scope 1 with assigned evidence, direct
    dependencies, exact SHA/diff, affected interfaces, and relevant tests.
40. Compile/type/reference evidence, a failing test, an unknown interface owner,
    an unresolved call path, or regression risk triggers a recorded scope
    escalation instead of guessing.
41. Developer, QA, Architect, Security/Reviewer, and Research use their bounded
    role-specific starting points and may widen scope when evidence requires it.
42. A repair-loop Context Delta records Packet ID/version, previous/new SHA,
    changed files/diff, new findings/tests, and unchanged constraints.
43. Compact specialist returns contain new status, evidence, tests, escalation,
    and blockers without repeating known project history.
44. Reliable analysis is reused, while independent QA, Security, containment,
    regression, and permission/safety validation remain mandatory.
45. Routing classifies duplicate-context risk Low/Medium/High without a token
    calculator; it may reduce low-value parallelism but not valid disjoint work.
46. Existing Threads begin new work from a current Packet; replacement still
    requires demonstrated contamination or another V1.1.1 replacement gate.
47. Context efficiency never lowers tests, QA, Security, Git checks, required
    dependency reading, blocker disclosure, or acceptance criteria.
48. Case A, a single-file small bug, stays Coordinator-only or uses one
    Developer, starts locally, and performs no full-repository scan.
49. Case B, a local Bridge, uses Developer plus QA; Developer starts from the
    assigned module and QA verifies exact SHA, diff, tests, and affected
    interfaces without reconstructing the whole project.
50. Case C, a true architecture refactor, permits Architect to widen its read
    scope when the system-wide decision requires it.
51. Case D, QA evidence of a cross-module side effect, permits and records a
    justified QA Scope escalation.
52. Case E, Developer to QA FAIL to Developer to QA, sends the initial full
    Packet once and uses versioned Context Deltas with exact SHAs thereafter.
53. Case F, two Developers with disjoint ownership and material parallel value,
    may work in parallel and may receive separate Worktrees within the Budget.
54. Final reporting includes concise Context Efficiency and Reuse Efficiency,
    including initial scopes, escalations, reused evidence, and justified
    duplicate full scans.
55. Registry remains schema 2; V1.2.0 adds no model/reasoning control, quota or
    billing system, savings percentage, service, database, or permission change.
56. Module Registry is a separate schema 1 file and Thread Registry remains
    schema 2 without module or lease objects mixed into it.
57. Shadow is the default project mode; a Shadow module preview does not create
    or update either Registry or write project metadata.
58. Active module governance requires an exact project-specific mode change and
    does not enable a similarly named project.
59. Persistent module records require `verifiedAt`,
    `verifiedAgainstCommit`, confidence, evidence sources, responsibility, path,
    owner, dependency, and lifecycle fields without treating the cache as truth.
60. First adoption may widen its read scope with a recorded reason and leaves
    uncertain responsibility `Unknown` instead of guessing from folder names.
61. Normal Existing Capability Check starts from the primary module, assigned
    evidence, and direct dependencies rather than a full-repository scan.
62. Existing Capability evidence is passed once in the Delegation Packet and
    specialists do not repeat the same adoption scan without evidence.
63. Similar names produce only a duplicate signal; adapters, providers,
    strategies, compatibility layers, and test doubles require behavioral and
    ownership evidence before `POSSIBLE_DUPLICATION` is decided.
64. One core module has one primary owner role, while one role may own several
    modules; a module never creates a visible task by itself.
65. An Active module write lease records module, writer Thread, task/Packet,
    Worktree, Branch/detached state, allowed paths, Base Commit, acquisition,
    verification, expiry, state, and release reason.
66. Lease expiry never permits silent takeover; stale recovery requires real
    Thread/Worktree/Branch/Git verification and recorded evidence.
67. A second writer for the same module is blocked until owner handoff, verified
    release/stale recovery, serial execution, or an explicit disjoint
    architecture split.
68. Architect routing is evidence-based: stable two-module work does not
    automatically add Architect, while changed contracts, uncertain ownership,
    shared state/data/permission/concurrency, or unresolved duplication does.
69. Module, impact, owner, capability, architecture, and lease fields extend the
    existing Delegation Packet; no parallel change document is required.
70. `REMOVABLE` is only a review state and never authorizes code, file, schema,
    Branch, or Worktree deletion.
71. Medium/high-risk QA separates Feature and Regression checks and verifies the
    exact SHA; uncovered old-behavior risk is reported rather than hidden.
72. Required Architecture Consistency PASS joins exact-SHA QA PASS in the
    integration gate, followed by post-integration regression.
73. Module governance policy fixtures A-H cover existing cancellation reuse,
    AI owner discovery, duplicate Session prevention, disjoint parallelism,
    same-module serialization, true cross-module architecture, simple local
    work, and regression-caused QA failure.
74. The always-loaded managed AGENTS body stays a concise entry contract; module
    schema and examples live only in on-demand references, and no unmeasured
    Token-saving percentage is promised.
75. Install/Disable/Enable/Uninstall retain both Registries. Backups record and
    copy existing Thread and Module Registry state with hashes without creating
    a missing Module Registry.
76. V1.3.0 retains every V1.2.0 context, lifecycle, adoption, Worktree Budget,
    Branch safety, read-only role, exact-SHA QA, and model/permission boundary.
77. `Validate-V1.ps1` invokes the current V1.3.3 validator, never a historical
    validator by mistake.
78. Historical validators run only against available frozen historical package
    snapshots and report `NOT_AVAILABLE` instead of failing the current root.
79. Package validation does not require a global AGENTS installation; Installed
    validation checks exactly one managed block and the V1.3.3 version.
80. Full acceptance distinguishes static, official, automated behavior, real
    Git, and real Codex App evidence; pending evidence is never counted as PASS.
81. Lease reuse requires exact module, writer, task/Packet, Packet version,
    Worktree, Branch/detached state, Base Commit, and allowed paths.
82. Active leases in different modules still conflict on exact, parent/child,
    or shared-file path scopes.
83. Module upsert preserves every unspecified authoritative field.
84. Confirmed modules reject missing responsibility, path, owner, lifecycle,
    source, verification time, or commit evidence.
85. Active mode records exact project authorization evidence; a command or
    similar project name is insufficient.
86. Active-to-Shadow is blocked while an Active lease remains.
87. Router upgrade/adoption/mode change preserves in-flight Developer/QA work
    through a recorded safe checkpoint.
88. Coordinator is the default Integration Owner; an alternate owner records
    role, Thread ID, target Branch, scope, reason, and authorization.
89. `Developer | 开发工程师` is canonical and reused before a narrower specialist
    when its verified scope fits; it is not mechanically mapped to Fullstack.
90. Git branch fixtures pass `git check-ref-format --branch` and use slash-based
    names rather than invalid backslash names.
91. Packet invalidation and capability-check refresh have explicit triggers and
    do not disguise boundary changes as same-version Context Deltas.
92. Level 0 performs no team discovery/adoption/creation, Worktree, lease,
    Packet, Registry mutation, full scan, Architect, or routine QA work.
93. Registry locks contain process identity and recover only verified stale
    locks after the threshold; uncertain lock ownership fails closed.
94. Registry writes preserve a parsed previous known-good `.bak`; unknown
    corruption is reported and not automatically restored.
95. An isolated real temporary Git lifecycle proves valid Branch/Worktree,
    exact commits, QA fail-repair-pass, containment, and safe cleanup rejection
    without a remote or any real-project mutation.
96. A directly readable Architect that returns the required visible role result
    remains `HEALTHY` and is not replaced.
97. One empty delivery followed by a successful controlled retry remains healthy
    and creates no replacement.
98. Two verified empty deliveries with clean Git/ReadOnly evidence mark the
    Thread `Degraded` and record `THREAD_DELIVERY_DEGRADED` evidence.
99. A delivery-degraded Thread remains distinct from `Stale` in schema 2.
100. A healthy exact-project/normalized-role Thread is adopted before creation.
101. With no healthy match, one replacement is allowed and preserves
     `ReplacesThreadId` plus incident lineage.
102. A replacement health check with visible `HEALTH_OK` passes before the real
     role Packet is sent.
103. If the only replacement also delivers no body/tools/conclusion, the incident
     becomes `CHANNEL_UNAVAILABLE` and a third role Thread is blocked.
104. A bounded low/medium-risk read-only architecture decision permits an
     explicitly labeled Coordinator fallback when all fallback gates pass.
105. Security, credential/auth architecture, irreversible migration, destructive
     database work, deployment authorization, major writer conflict, same-run
     production-code editing, or an independent-Architect requirement blocks
     Coordinator fallback.
106. Repository change during Coordinator fallback produces a failed ReadOnly
     Guard and cannot satisfy the Architecture Gate.
107. Replacement/fallback reuses capability evidence when the exact Baseline SHA
     and scope remain valid and performs no duplicate full scan.
108. Normal Developer completion records a compact Receipt, reconciles the
     matching primary body, and reaches `ACKNOWLEDGED` without weakening QA.
109. Normal QA PASS records its exact role result and closes through Receipt,
     reconciliation, and Coordinator ACK.
110. A missing primary body with a complete valid Receipt restores the formal
     PASS/FAIL/BLOCKED result without asking the user to copy it.
111. A missing primary body and missing/incomplete Receipt requests exactly one
     controlled `REDELIVER` of the existing compact summary.
112. Successful redelivery records/reuses that summary, reconciles it, and
     reaches `ACKNOWLEDGED` without reexecuting the assignment.
113. Any critical disagreement between primary body and Receipt records
     `DELIVERY_EVIDENCE_CONFLICT`, fails closed, and forbids ACK.
114. Controlled redelivery performs no tests, build, network, Provider request,
     Developer rerun, or Specialist creation.
115. Receipt persistence rejects secrets, Authorization/credentials,
     prompt/completion/reasoning bodies, raw Provider/SSE, large logs, and full
     chat history.

## Required evidence

- frozen V1 snapshot path and per-file hashes;
- exact visible task titles, IDs, reused/created state, worktrees, branches,
  commits, and archive state;
- Registry schema, adoption events, budget status, and direct read result;
- before/after read-only guard reports;
- QA FAIL, owner rework, new SHA, QA PASS, integration SHA, regression output;
- automatic test JSON and official validator output;
- Case A-F context-delegation simulation output;
- Module Registry mutation/lease test output and Module governance Cases A-H;
- managed AGENTS size/duplication checks and Shadow no-write evidence;
- verified limitations, especially current wrapper pagination and lack of a
  hard read-only sandbox.
