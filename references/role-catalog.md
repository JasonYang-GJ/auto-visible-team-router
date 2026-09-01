# Extensible Role Catalog

Use the canonical key for matching and the Chinese label for task titles. Add a
new role here when a genuinely distinct recurring responsibility appears; do
not rewrite the router.

| Canonical key | Title label | Select when | Common aliases |
|---|---|---|---|
| Architect | 架构师 | system boundaries, major cross-module design, large refactor, important data/security architecture, or several specialists need one contract | architecture, system design |
| Developer | 开发工程师 | an existing general implementation owner can safely handle the bounded change, or the codebase does not justify a narrower specialty | developer, engineer, coder |
| Frontend | 前端 | web/desktop UI implementation, responsive layout, client state, or interaction behavior | UI engineer, web frontend |
| Backend | 后端 | APIs, services, server logic, authorization enforcement, or integrations | API engineer, server |
| Fullstack | 全栈 | one bounded vertical slice is safer with one implementation owner than two editors | developer, application engineer |
| AI | AI工程师 | model integration, prompts/evals, RAG, speech/vision pipelines, or inference behavior | ML engineer, LLM engineer |
| Voice | 语音工程师 | audio capture/playback, VAD, ASR/TTS, wake word, barge-in, echo control, or voice-device lifecycle | audio engineer, speech engineer |
| Windows | Windows工程师 | Windows APIs, services, shell, registry, packaging, desktop hooks, or OS integration | desktop engineer, system engineer |
| Mobile | 移动端 | native or cross-platform phone/tablet code and device lifecycle | iOS, Android, Flutter, React Native |
| Database | 数据工程师 | schema design, migration, query correctness, data quality, or pipelines | DBA, data engineer |
| DevOps | DevOps | CI/CD, packaging, deployment infrastructure, runtime operations | release engineer, platform engineer |
| Security | 安全 | threat modeling, auth review, permission boundaries, secrets, privacy, adversarial checks | security reviewer |
| Research | 技术研究 | time-bounded evidence gathering or comparison before a decision | explorer, investigator |
| UX | 产品体验 | user flows, information architecture, accessibility, or usability evidence without owning implementation | product designer, UX reviewer |
| QA | QA | independent functional, integration, regression, reliability, or release verification | tester, test engineer |
| Reviewer | 代码审查 | fresh-eyes code/design review after implementation or repeated rejection | code reviewer |

## Architect gate

Select Architect only for a new system architecture, a major multi-module or
cross-frontend/backend change, significant data/AI/security architecture, a
large refactor, competing technical routes with long-term consequences, or a
need to coordinate interfaces among several specialists. Do not select it for a
normal page, endpoint, configuration change, or small bug.

Architect is Policy-Enforced Read Only and returns decisions/contracts, not
product code. Capture and compare the repository guard before and after work;
this detects policy violations but is not a hard sandbox guarantee.
For a local interface, bridge, or refactor, start with the affected modules;
selecting Architect does not automatically justify a repository-wide scan.
An idle/completed Architect is healthy only when its visible return satisfies
the architecture contract. For a missing primary body, reconcile exact Thread
output and the compact Receipt through
[delivery-reliability.md](delivery-reliability.md); only an unrecoverable empty
delivery proceeds to [visible-thread-delivery-recovery.md](visible-thread-delivery-recovery.md),
never Stale relabeling or repeated Architect creation.

## QA gate

Prefer independent QA for medium/large features, multi-file or cross-layer
changes, migrations, concurrency, permissions/security, critical user flows,
high-impact bugs, and release preparation. Do not create QA merely to validate
a tiny low-risk edit that the coordinator can check directly.

QA is Policy-Enforced Read Only. It does not change product code to make a test
pass. A failure goes back to the owning implementer, the repair produces a new
commit SHA, and QA verifies that exact SHA before integration and regression.
QA starts from that SHA, its diff, affected interfaces, acceptance criteria, and
relevant tests, then records any evidence-driven Read Scope escalation.

## Reviewer and escalation gate

Reviewer is not a permanent companion to every developer. Add it for
consequential review, ambiguous correctness, repeated QA rejection, or when the
implementer cannot independently validate the work. Add Architect during
escalation only when the new evidence is architectural, not just because a test
failed. Reviewer, Research, and Security are also Policy-Enforced Read Only
unless the user explicitly changes the implementation authorization.

## Normalization and reuse

Normalize existing titles to the closest canonical role only when project
identity also matches. `UI` can map to Frontend for implementation or UX for
flow/usability work; inspect its bounded responsibility rather than the word
alone. `Developer` is a canonical reusable role, not an automatic alias for
Fullstack. Reuse an accessible existing Developer before creating Frontend,
Backend, Fullstack, Voice, AI, or another narrower role when its verified scope
already covers the bounded assignment.

Match a module owner to the smallest suitable existing role. Modules and roles
are not one-to-one: one Voice Thread may own capture, VAD, and ASR modules, and
one AI Thread may own prompt and intent modules. Never create a visible task
only because a new module ID exists.

If two visible tasks already represent one normalized role, reuse the most
recent accessible task with clean relevant context. Do not create a third.
Report the duplicate rather than archiving or deleting it without authorization.

For every selected role, use the role-specific starting points and compact
returns in [context-delegation.md](context-delegation.md).
