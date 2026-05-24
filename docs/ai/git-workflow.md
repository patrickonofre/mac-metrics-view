# Git workflow

Single repo, `main` is the integration branch.

## Branches

- Branch off `main`. Name by intent: `feat/temperature-menu-bar`, `fix/network-delta`,
  `refactor/sampler-protocol`, `docs/ai-structure`.
- Keep a branch scoped to one logical change. Don't accumulate unrelated work.

## Commits

- Imperative, present tense, scoped: `Add temperature menu bar segment`,
  `Fix negative network rate on counter reset`.
- One logical change per commit where practical. Don't commit build artifacts
  (`.build/`, `DerivedData/`, `*.app`, the beta zip are ignored / should not be added).
- Don't commit secrets or signing material.

## Pull requests

- One logical change per PR. Title under ~70 chars, imperative.
- Body explains the **why**, links the relevant `docs/ai/plans|specs|tasks` artifact,
  and points to the VALIDATION record (`docs/ai/validation/`).
- Include a test plan: what `swift test` covered and, for UI/status-item changes, that
  the app was launched and the behavior observed (see
  [`testing-standards.md`](testing-standards.md)).
- Don't bundle refactors into a feature PR. Don't merge with failing `swift test`.

## Before opening a PR

```sh
swift build && swift test
```

For UI/menu bar changes, also launch the app (`swift run` or the Xcode build) and
confirm the behavior — a green build is not proof the status item behaves.

## What stays out of version control

`.gitignore` excludes `.build/`, `.swiftpm/`, `DerivedData/`, `*.xcuserstate`, and
`xcuserdata/`. The generated `MacMetricsView.app` and `MacMetricsView-beta.zip`
artifacts are build outputs — keep them out of commits.
