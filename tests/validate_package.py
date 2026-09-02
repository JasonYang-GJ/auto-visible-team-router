from __future__ import annotations
from pathlib import Path
import json
import re
import sys
from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[1]
failures = []
passes = []

def check(name: str, condition: bool, detail: str = ""):
    if condition:
        passes.append(name)
    else:
        failures.append((name, detail))

required = [
    "SKILL.md","README.md","VERSION",
    "references/modes-and-mutual-exclusion.md",
    "references/project-identity.md",
    "references/repository-containment.md",
    "references/workstream-routing.md",
    "references/execution-backends.md",
    "references/platform-capability-history.md",
    "references/dependency-planning.md",
    "references/context-delegation.md",
    "references/risk-gates.md",
    "references/thread-lifecycle.md",
    "references/git-worktree-safety.md",
    "references/delivery-reliability.md",
    "references/telemetry-ab.md",
    "references/migration-v1.md",
    "references/canary-runbook.md",
    "references/acceptance-tests.md",
    "scripts/Manage-Global.ps1",
    "scripts/Resolve-ProjectIdentity.ps1",
    "scripts/Resolve-RepositoryContainment.ps1",
    "scripts/Resolve-Route.ps1",
    "scripts/Resolve-ExecutionBackend.ps1",
    "scripts/Workstream-Registry.ps1",
    "scripts/ReadOnly-Guard.ps1",
    "scripts/Validate-Router.ps1",
    "schemas/defaults.json",
    "schemas/project-identity.schema.json",
    "schemas/repository-containment.schema.json",
    "schemas/route-proposal.schema.json",
    "schemas/workstream-registry.schema.json",
    "tests/scenarios.json",
    "tests/Run-OfflineGate.ps1",
    "tests/Run-ReleaseCandidateGate.ps1",
    "tests/Test-InstallRollback.ps1",
    "tests/Test-ManagementLifecycle.ps1",
    "tests/Test-ReadOnlyGuard.ps1",
    "tests/Test-RouteAcceptance.ps1",
    "tests/Test-BackendSelection.ps1",
    "tests/Test-PlatformAdaptedSynthetic.ps1",
    "tests/Test-ProjectIdentity.ps1",
    "tests/Test-RepositoryContainment.ps1",
    "tests/Test-WorkstreamRegistry.ps1",
    "templates/AGENTS-v2-shadow.md",
    "templates/AGENTS-v2-active.md",
]

for rel in required:
    check(f"file:{rel}", (ROOT / rel).is_file(), "missing")

version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
check("version-v2", version == "2.0.0", version)

defaults = json.loads((ROOT / "schemas/defaults.json").read_text(encoding="utf-8"))
check("default-mode-shadow", defaults["defaultMode"] == "SHADOW", str(defaults))
check("lane-cap-3", defaults["maxCodingLanes"] == 3, str(defaults))
check("worktree-budget-3", defaults["worktreeBudget"] == 3, str(defaults))
check("default-backend-current-thread", defaults["defaultExecutionBackend"] == "CURRENT_THREAD", str(defaults))
check("backend-selection-order", defaults["executionBackendSelectionOrder"] == ["CURRENT_THREAD", "COLLAB_SUBAGENT", "MANUAL_VISIBLE_WORKTREE", "AUTO_VISIBLE_WORKTREE"], str(defaults))
check("auto-visible-unsupported", defaults["executionBackends"]["AUTO_VISIBLE_WORKTREE"]["availability"] == "UNSUPPORTED", str(defaults))
check("auto-visible-dispatch-disabled", defaults["executionBackends"]["AUTO_VISIBLE_WORKTREE"]["productionDispatchEnabled"] is False, str(defaults))
check("collab-shared-checkout", defaults["executionBackends"]["COLLAB_SUBAGENT"]["independentCheckout"] is False, str(defaults))
check("collab-coding-forbidden", defaults["executionBackends"]["COLLAB_SUBAGENT"]["codingParallelism"] == "FORBIDDEN", str(defaults))
check("parallel-serialized-fallback", defaults["parallelBackendUnavailablePolicy"] == "SERIALIZED_FALLBACK", str(defaults))
check("telemetry-default-off", defaults["telemetryEnabledByDefault"] is False, str(defaults))
check("registry-key-v2", defaults["registryKey"] == ["projectKey","batchId","workstreamId"], str(defaults))
check("project-identity-priority", defaults["projectIdentityPriority"] == ["APP_PROJECT_ID","GIT_ROOT","CANONICAL_PATH"], str(defaults))
check("project-key-prefixes", defaults["projectKeyPrefixes"] == ["id:","git:","path:"], str(defaults))
check("project-id-not-required", defaults["projectIdRequired"] is False, str(defaults))
check("thread-cwd-not-project-identity", defaults["threadCwdIsProjectIdentity"] is False, str(defaults))
check("containment-resolver", defaults["repositoryContainmentResolver"] == "scripts/Resolve-RepositoryContainment.ps1", str(defaults))
check("mutual-exclusion", defaults["activeRouterMutualExclusionRequired"] is True, str(defaults))

skill = (ROOT / "SKILL.md").read_text(encoding="utf-8")
check("frontmatter-name", "name: auto-visible-team-router" in skill)
check("dual-router-block", "DUAL_ROUTER_BLOCKED" in skill)
check("extra-agent-hard-rule", "Every additional Agent must own an independent" in skill)
check("thread-temporary-memory", "A Codex Thread is temporary working memory." in skill)
check("no-token-percentage", "promise a Token-saving percentage" in skill)
check("local-route", "`LOCAL`" in skill)
check("parallel-3-route", "`PARALLEL_3`" in skill)
check("logical-backend-decoupling", "Logical routing is separate from execution placement" in skill)
check("auto-visible-platform-freeze", "`AUTO_VISIBLE_WORKTREE` — `UNSUPPORTED`" in skill)
check("serialized-fallback", "`SERIALIZED_FALLBACK`" in skill)

# Verify all relative markdown links from SKILL exist.
for target in re.findall(r"\]\(([^)]+\.md)\)", skill):
    p = ROOT / target
    check(f"skill-link:{target}", p.is_file(), "broken local link")

# JSON parse.
for rel in [
    "schemas/defaults.json",
    "schemas/project-identity.schema.json",
    "schemas/repository-containment.schema.json",
    "schemas/route-proposal.schema.json",
    "schemas/workstream-registry.schema.json",
    "tests/scenarios.json",
]:
    try:
        json.loads((ROOT / rel).read_text(encoding="utf-8"))
        check(f"json:{rel}", True)
    except Exception as exc:
        check(f"json:{rel}", False, repr(exc))

# Validate representative instances against the shipped JSON Schemas. Four
# deliverables must be representable even though only three may run at once.
route_schema = json.loads((ROOT / "schemas/route-proposal.schema.json").read_text(encoding="utf-8"))
registry_schema = json.loads((ROOT / "schemas/workstream-registry.schema.json").read_text(encoding="utf-8"))
identity_schema = json.loads((ROOT / "schemas/project-identity.schema.json").read_text(encoding="utf-8"))
containment_schema = json.loads((ROOT / "schemas/repository-containment.schema.json").read_text(encoding="utf-8"))
route_fixture = {
    "mode": "SHADOW",
    "route": "PARALLEL_3",
    "logical_route": "PARALLEL_3",
    "execution_backend": "CURRENT_THREAD",
    "execution_mode": "SERIALIZED_WAVES",
    "parallel_degraded": True,
    "batch_id": "fixture",
    "objective": "four deliverables in two waves",
    "deliverables": [
        {"id": f"d{i}", "outcome": f"outcome {i}", "dependencies": [], "acceptance": ["PASS"]}
        for i in range(4)
    ],
    "max_parallel_coding_lanes": 3,
    "risk_gates": {"architect": False, "qa": True, "security": False, "reviewer": False},
}
registry_fixture = {
    "schemaVersion": 1,
    "defaults": {"worktreeBudget": 3, "maxCodingLanes": 3},
    "projects": {
        "git:c:\\fixture": {
            "projectIdentity": {
                "projectKey": "git:c:\\fixture",
                "source": "GIT_ROOT",
                "projectId": None,
                "canonicalGitRoot": "C:\\fixture",
                "canonicalGitCommonDir": "C:\\fixture\\.git",
            },
            "batches": {
                "batch-fixture": {
                    "batchId": "batch-fixture",
                    "objective": "containment fixture",
                    "state": "ACTIVE",
                    "workstreams": {
                        "lane-a": {
                            "workstreamId": "lane-a",
                            "state": "RUNNING",
                            "threadIdentity": {"threadId": "thread-a"},
                            "checkoutIdentity": {
                                "checkoutPath": "C:\\fixture-wt",
                                "checkoutType": "CODEX_MANAGED_WORKTREE",
                                "gitCommonDir": "C:\\fixture\\.git",
                                "startingSha": "a" * 40,
                                "containmentCategory": "RELATED_GIT_WORKTREE",
                                "containmentStatus": "PASS",
                            },
                            "worktreeIdentity": {
                                "management": "CODEX_MANAGED",
                                "createdByRouter": False,
                                "routerCreationEvidence": None,
                            },
                            "branchIdentity": {"branchOrDetached": "DETACHED"},
                        }
                    },
                }
            },
        }
    },
}
identity_fixture = {
    "status": "PASS",
    "projectIdentitySource": "GIT_ROOT",
    "projectKey": "git:c:\\fixture",
    "projectId": None,
    "canonicalGitRoot": "C:\\fixture",
    "canonicalPath": "C:\\fixture",
    "headSha": "a" * 40,
    "remoteUrl": None,
    "repositoryIdentity": {"canonicalRoot": "C:\\fixture", "headSha": "a" * 40, "remoteUrl": None},
    "blocker": None,
}
containment_fixture = {
    "threadId": "thread-a",
    "threadCwd": "C:\\fixture-wt",
    "threadGitRoot": "C:\\fixture-wt",
    "threadGitDir": "C:\\fixture\\.git\\worktrees\\fixture-wt",
    "threadGitCommonDir": "C:\\fixture\\.git",
    "canonicalGitRoot": "C:\\fixture",
    "canonicalGitCommonDir": "C:\\fixture\\.git",
    "projectKey": "git:c:\\fixture",
    "worktreeInventoryMatch": True,
    "appManagedEvidenceMatch": False,
    "startingSha": "a" * 40,
    "batchBaselineSha": "a" * 40,
    "lineageExplained": True,
    "branchOrDetached": "DETACHED",
    "checkoutType": "CODEX_MANAGED_WORKTREE",
    "containment": "RELATED_GIT_WORKTREE",
    "containmentStatus": "PASS",
    "dirtyPaths": [],
    "dirtyStateAttributed": True,
    "management": "CODEX_MANAGED",
    "createdByRouter": False,
    "blocker": None,
}
for name, schema, instance in [
    ("project-identity", identity_schema, identity_fixture),
    ("repository-containment", containment_schema, containment_fixture),
    ("route-proposal", route_schema, route_fixture),
    ("workstream-registry", registry_schema, registry_fixture),
]:
    errors = list(Draft202012Validator(schema).iter_errors(instance))
    check(f"schema-instance:{name}", not errors, "; ".join(error.message for error in errors))

scenarios = json.loads((ROOT / "tests/scenarios.json").read_text(encoding="utf-8"))
check("scenario-count>=34", len(scenarios) >= 34, str(len(scenarios)))
ids = [x["id"] for x in scenarios]
check("scenario-ids-unique", len(ids) == len(set(ids)))
check("shadow-scenario", any(x["id"] == "S16_shadow_no_side_effects" for x in scenarios))
check("dual-router-scenario", any(x["id"] == "S17_dual_router_unknown" for x in scenarios))
check("no-role-reuse-scenario", any(x["id"] == "S18_new_batch_no_role_reuse" for x in scenarios))
check("serialized-fallback-scenario", any(x["id"] == "S27_parallel2_serialized_fallback" for x in scenarios))
check("auto-visible-unsupported-scenario", any(x["id"] == "S29_auto_visible_unsupported" for x in scenarios))
check("manual-visible-scenario", any(x["id"] == "S30_manual_visible_ready" for x in scenarios))
check("ordinary-feature-not-blocked", any(x["id"] == "S33_ordinary_feature_not_blocked" for x in scenarios))

# V1 isolation in management script.
manage = (ROOT / "scripts/Manage-Global.ps1").read_text(encoding="utf-8")
check("install-default-shadow", "mode = 'SHADOW'" in manage)
check("v1-no-delete-command", "Remove-Item -Recurse -Force -LiteralPath $v1Runtime" not in manage)
check("canary-confirm-single-router", "ConfirmSingleRouter" in manage)
check("uninstall-retains-runtime", "runtime, backups, and legacy archives retained" in manage)
check("agents-v1-replaced", "Set-AgentsRouterBlock" in manage and "AllowV1Replacement" in manage)
check("legacy-registry-archive", "legacy-v1" in manage and "ARCHIVED_NOT_MIGRATED" in manage)
check("fresh-workstream-registry", "workstream-registry.json" in manage and "projects = [ordered]@{}" in manage)
check("explicit-skill-root", "[string]$SkillRoot" in manage)
check("exact-v2-shadow-update", "'UpdateV2Shadow'" in manage)
check("exact-source-identity", "[string]$SourceIdentity" in manage and "installedSourceIdentity" in manage)
check("previous-v2-backup", "previousV2Backup" in manage and "v2-pre-update-" in manage)
check("exact-update-fresh-registry", "V2_EXACT_SHADOW_UPDATE_PASS" in manage)

# Read-only guard contract.
guard = (ROOT / "scripts/ReadOnly-Guard.ps1").read_text(encoding="utf-8")
check("readonly-confirmed", "READ_ONLY_CONFIRMED" in guard)
check("readonly-changed", "READ_ONLY_STATE_CHANGED" in guard)
check("guard-no-reset-clean", "git reset" not in guard.lower() and "git clean" not in guard.lower())

# Registry does not use permanent role as key.
registry = (ROOT / "scripts/Workstream-Registry.ps1").read_text(encoding="utf-8")
check("registry-workstream-key", "WorkstreamId" in registry and "BatchId" in registry)
check("registry-no-role-key", "Role" not in registry)
check("registry-fail-closed-lock", "WORKSTREAM_REGISTRY_LOCKED" in registry)
check("registry-known-good-backup", '"$Path.bak"' in registry)

identity_resolver = (ROOT / "scripts/Resolve-ProjectIdentity.ps1").read_text(encoding="utf-8")
check("identity-project-id-preferred", "APP_PROJECT_ID" in identity_resolver)
check("identity-git-fallback", "GIT_ROOT" in identity_resolver)
check("identity-path-fallback", "CANONICAL_PATH" in identity_resolver)
check("identity-blocked", "PROJECT_IDENTITY_BLOCKED" in identity_resolver)

containment_resolver = (ROOT / "scripts/Resolve-RepositoryContainment.ps1").read_text(encoding="utf-8")
check("containment-common-dir", "git-common-dir" in containment_resolver)
check("containment-inventory", "worktree" in containment_resolver and "--porcelain" in containment_resolver)
check("containment-unrelated", "UNRELATED_CHECKOUT" in containment_resolver)
check("containment-dirty", "UNATTRIBUTED_DIRTY_STATE" in containment_resolver)
check("containment-lineage", "BASELINE_LINEAGE_UNEXPLAINED" in containment_resolver)

backend_resolver = (ROOT / "scripts/Resolve-ExecutionBackend.ps1").read_text(encoding="utf-8")
check("backend-current-thread", "CURRENT_THREAD" in backend_resolver)
check("backend-collab", "COLLAB_SUBAGENT" in backend_resolver)
check("backend-manual-visible", "MANUAL_VISIBLE_WORKTREE" in backend_resolver)
check("backend-auto-visible-unsupported", "THREAD_CREATION_PLATFORM_LIMITATION" in backend_resolver)
check("backend-no-create-thread", "create_thread" not in backend_resolver)
check("backend-serialized-fallback", "SERIALIZED_FALLBACK" in backend_resolver)

release_gate = (ROOT / "tests/Run-ReleaseCandidateGate.ps1").read_text(encoding="utf-8")
check("release-gate-exact-sha", "ExpectedSha" in release_gate and "rev-parse HEAD" in release_gate)
check("release-gate-clean-before-after", release_gate.count("status --porcelain") >= 2)
check("release-gate-offline-marker", "V2_OFFLINE_ENGINEERING_PASS" in release_gate)
check("release-gate-pass-marker", "V2_RELEASE_CANDIDATE_GATE_PASS" in release_gate)

for retired in [
    "references/routing-policy.md",
    "references/role-catalog.md",
    "references/module-governance.md",
    "scripts/Thread-Registry.ps1",
    "scripts/Module-Registry.ps1",
    "scripts/Validate-V1.3.3.ps1",
]:
    check(f"retired:{retired}", not (ROOT / retired).exists(), "conflicting V1 file remains")

# Compatibility/static PowerShell checks.
for rel in ["scripts/Manage-Global.ps1","scripts/Resolve-ProjectIdentity.ps1","scripts/Resolve-RepositoryContainment.ps1","scripts/Resolve-Route.ps1","scripts/Resolve-ExecutionBackend.ps1","scripts/Workstream-Registry.ps1","scripts/ReadOnly-Guard.ps1","scripts/Validate-Router.ps1"]:
    ptext = (ROOT / rel).read_text(encoding="utf-8")
    check(f"powershell-no-asHashtable:{rel}", "-AsHashtable" not in ptext)
    check(f"powershell-no-dangerous-reset:{rel}", "git reset --hard" not in ptext.lower())
    check(f"powershell-no-dangerous-clean:{rel}", "git clean -fd" not in ptext.lower())
    check(f"powershell-brace-balance:{rel}", ptext.count("{") == ptext.count("}"),
          f"open={ptext.count('{')} close={ptext.count('}')}")
    check(f"powershell-paren-balance:{rel}", ptext.count("(") == ptext.count(")"),
          f"open={ptext.count('(')} close={ptext.count(')')}")

print(f"V2_PACKAGE_CHECKS_PASS={len(passes)}")
print(f"V2_PACKAGE_CHECKS_FAIL={len(failures)}")
if failures:
    for name, detail in failures:
        print(f"FAIL {name}: {detail}")
    sys.exit(1)
print("V2_OFFLINE_STATIC_PASS")
