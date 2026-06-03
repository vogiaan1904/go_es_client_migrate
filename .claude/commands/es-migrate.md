---
description: Phase 1 — migrate Go ES files from olivere/elastic to esclient wrappers (go-elasticsearch v9), one file at a time with a build gate.
argument-hint: "[file-path | audit | all]"
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Task
---

Phase 1 of the ES 6.x→9.x migration. Follow the `esclient-wrapper-migrate`
skill. **The authority is `go build ./...`, not the reference doc's code.** Work
on a temp branch only — never on `main`.

Argument: `$1`

## Pre-flight (always)

1. Confirm the current branch is NOT `main`/`master`. If it is, STOP and tell the
   user to create a temp branch first (e.g. `git switch -c es9-migration`).
2. `go build ./...` to record the starting state.

## Mode: `audit` (or no argument)

Do not edit anything. Produce a migration plan:

- `grep -rnE 'github.com/olivere/elastic|elastic\.New' --include='*.go' .` to list
  every file and construct that still uses olivere.
- Group files by the constructs they use; flag the **non-mechanical hotspots**:
  `NewTermQuery`/`NewTermsQuery` (value wrapping), `NewRangeQuery` (type split),
  `NewFilterAggregation` (constructor arg), `NewAvgAggregation` (rename), sort,
  `TotalHits()`, `hit.Source`.
- Note whether the `esclient` package already exposes a wrapper for each
  construct, or whether one must be added.
- Output an ordered file list (leaf/low-risk files first, shared `esclient`
  package changes first of all) and stop. Recommend running `/es-migrate <file>`
  per file, or `/es-migrate all`.

## Mode: `<file-path>`

Dispatch the `es-migrator` subagent for that one file. After it returns, verify
`go build ./...` is green and the file has no `olivere`/`esdsl`/`types` imports.
Report the result and the next file to do.

## Mode: `all`

For each file from the audit, in order, dispatch the `es-migrator` subagent. Run
`go build ./...` after **each** file — if it goes red and the agent could not fix
it, stop and report rather than cascading edits onto a broken build. Summarize at
the end: files migrated, wrappers added to `esclient`, and every
`TODO(es-migrate)` left behind (these feed Phase 2).

## Done criteria for Phase 1

- `go build ./...` and `go vet ./...` are green.
- `grep -rnE 'olivere' --include='*.go' .` is empty.
- `typedapi/esdsl` and `typedapi/types` appear ONLY inside the `esclient`
  package.
- Existing tests pass. Remind the user: Phase 1 proves it **compiles**, not that
  queries are runtime-identical — that is Phase 2 (`/es-golden-capture` then
  `/es-golden-verify`).
