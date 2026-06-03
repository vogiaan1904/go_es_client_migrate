---
description: Phase 2.1 — capture golden query+response JSON baselines from the OLD olivere code against ES 6.x.
argument-hint: "<file-path> [more-files...]"
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Task
---

Phase 2.1 of the ES migration: record the behavior of the OLD code as golden
files, so Phase 2.2 can prove the migrated code reproduces it. Follow the
`es-golden-master` skill.

Files: `$ARGUMENTS`

## Pre-flight

1. Confirm you are on the OLD branch (`main`, still olivere, NOT the Phase 1 temp
   branch). If not, STOP — capturing on migrated code defeats the purpose.
2. Confirm ES 6.x is reachable: `ES_URL` is set and `curl "$ES_URL"` returns a
   6.x version. If `ES_URL` is unset, ask the user for it (and `ES_AUTH` if
   needed) — do not invent one.
3. Confirm `go build ./...` is green so generated tests can run.

## Run

For each file in `$ARGUMENTS`, dispatch the `es-golden-runner` subagent in
**capture** mode, passing the file, `ES_URL`, the index, and the golden dir
(`testdata/es-golden/`).

If no file is given, first list candidates: `grep -rlE 'esclient\.'
--include='*.go' .`, group by package, surface the functions with the most
branching (highest-value cases), and recommend an order. Remind the user that
**case quality matters more than coverage breadth** — a few files captured
thoroughly beats many files captured shallowly.

## After

- Summarize: files captured, cases per function, any functions that could not be
  isolated.
- Tell the user to **commit `testdata/es-golden/**`** — it is the immutable
  contract for Phase 2.2.
- Next step: merge Phase 1, upgrade ES to 9, restore the same data, then run
  `/es-golden-verify` on the same files.
