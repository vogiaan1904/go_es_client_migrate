---
description: Phase 2.2 — verify the migrated code (ES 9) reproduces the golden request/response baselines; fix wrong mismatches until green.
argument-hint: "<file-path> [more-files...]"
allowed-tools: Read, Edit, Write, Bash, Grep, Glob, Task
---

Phase 2.2 of the ES migration: prove the migrated code generates the same
queries and gets the same results as the OLD code did. Follow the
`es-golden-master` skill; fix wrong mismatches with the `es-query-equivalence`
skill.

Files: `$ARGUMENTS`

## Pre-flight

1. Confirm Phase 1 is merged and `go build ./...` is green.
2. Confirm ES **9** is reachable and `curl "$ES_URL"` reports a 9.x version, with
   the SAME data/index the golden was captured against (restore the snapshot if
   needed). If `ES_URL` is unset, ask — do not invent one.
3. Confirm `testdata/es-golden/**` exists (the Phase 2.1 baseline). If missing,
   STOP — run `/es-golden-capture` on the old branch first.

## Run

For each file in `$ARGUMENTS`, dispatch the `es-golden-runner` subagent in
**verify** mode. The agent will: regenerate `.req.new.json` + `.res.new.json`,
`compare.sh` against the golden, classify each diff (benign vs wrong via
`known-benign-diffs.md`), and for every WRONG diff invoke `es-query-equivalence`,
fix the wrapper/caller, rebuild, and re-compare until clean.

Run files one at a time; do not move on while a file still has unresolved wrong
mismatches.

## After

- Report per file/case: PASS, benign-accepted (which fields), fixed (what
  changed and why), or still-failing (with the diff).
- The migration is verified for a file only when every case's request AND
  response match modulo documented-benign differences.
- Do NOT edit or regenerate the golden `.req.json`/`.res.json` files to make
  diffs disappear — that erases the contract. Only `*.new.json` are
  regenerated; the golden is fixed.
