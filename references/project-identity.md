# V2 Project identity contract

Project identity is resolved independently from visible Thread placement.
`thread.projectId` is preferred evidence, not a hard requirement for a local
Codex repository or folder.

`Thread cwd` is checkout placement, never Project Identity. After resolving
the canonical project, apply [repository-containment.md](repository-containment.md)
to each visible Thread checkout.

## Resolution priority

Use the first identity whose evidence is available:

1. app-native Project ID -> `id:<projectId>`;
2. canonical Git root with an exact HEAD -> `git:<canonical-git-root>`;
3. unambiguous canonical local path -> `path:<canonical-path>`.

A Git remote is optional metadata. A local repository without `origin` remains
a valid Git identity.

Return `PROJECT_IDENTITY_BLOCKED` only when Project ID, Git identity, and an
unambiguous canonical path are all unavailable.

## Canonical path rules

- resolve an absolute path;
- for Git identity, use `git rev-parse --show-toplevel` rather than cwd or a
  display title;
- remove trailing directory separators except for a filesystem root;
- on Windows, compare and key paths case-insensitively by using a lower-case
  invariant identity component;
- preserve the resolved native absolute path separately as evidence;
- never identify a project by its displayed title alone.
- never replace the canonical project key with a Worktree's physical path.

## Registry and Thread identity

The Registry identity remains:

```text
project_key + batch_id + workstream_id
```

New V2 batches accept only `id:`, `git:`, or `path:` project keys. Historical
diagnostic data may remain readable but is not automatically adopted.

A matching repository path is not enough to reuse a Thread. Adoption requires
the exact current `project_key + batch_id + workstream_id`, objective, and
ownership contract. Old V1 `Developer`, `QA`, `Architect`, or `Security`
Threads are not adopted merely because their role title or repository matches.

## Public resolver

Use `scripts/Resolve-ProjectIdentity.ps1` to resolve structured evidence before
opening a batch. The result records:

- `status`;
- `projectIdentitySource`;
- `projectKey`;
- optional `projectId`;
- `canonicalGitRoot` and `headSha` when Git-backed;
- optional `remoteUrl`;
- `canonicalPath`;
- exact blocker when unresolved.
