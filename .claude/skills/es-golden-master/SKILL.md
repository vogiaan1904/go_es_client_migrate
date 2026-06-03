---
name: es-golden-master
description: >-
  Prove the olivere→esdsl Elasticsearch migration is behavior-preserving using
  golden-master (characterization) testing. Use this to capture baseline request
  query JSON + ES response JSON from the OLD code (Phase 2.1) and to compare the
  NEW code's request/response against that baseline after upgrading to ES 9
  (Phase 2.2). Triggers: "golden", "characterization test", "compare query JSON",
  "prove queries identical", "es migration verification".
---

# ES Golden-Master Verification (Phase 2)

Phase 1 (`esclient-wrapper-migrate`) proves the new code **compiles**. It does
NOT prove the generated Elasticsearch queries are the same at runtime. Phase 2
proves that, empirically, by recording what the old code produced and asserting
the new code reproduces it.

Two sub-phases run on two different checkouts:

- **2.1 CAPTURE** — on `main` (OLD olivere code, ES 6.x running): record golden
  request bodies + responses.
- **2.2 VERIFY** — after merging Phase 1 and upgrading to ES 9: regenerate and
  compare against the golden files; fix mismatches.

## Honest scope — read before you start

The hard, **non-mechanical** step is "extract every `esclient` call into a
runnable test with realistic + edge-case inputs." This is per-file engineering
judgment, not a sweep:

- You must understand each function's inputs to choose meaningful cases
  (empty string, nil slice, zero, unicode, very large `size`, special chars that
  affect query_string, boundary dates for ranges, multi-value terms, etc.).
- Some `esclient` calls are buried behind branching logic; a single function can
  emit several different queries depending on args. Each branch needs a case.
- A thin/auto-generated baseline gives false confidence. **Quality of the input
  cases is the quality of the whole proof.** Say so to the user, and prefer
  fewer files with thorough cases over many files with one case each.

If a function's query can't be isolated without executing a live search, note it
and capture via the live ES round-trip (the replay script) rather than skipping.

## Golden file layout

```
testdata/es-golden/<pkg>/<file>/<func>/<case>.req.json   # generated query body (the request)
testdata/es-golden/<pkg>/<file>/<func>/<case>.res.json   # ES response, normalized
testdata/es-golden/<pkg>/<file>/<func>/<case>.meta.json  # {index, method, path, es_version}
```

Same paths are written in 2.1 and read in 2.2. Never overwrite `.req`/`.res`
golden files during VERIFY — write `*.new.json` next to them and diff.

**What carries from 2.1 to 2.2 — and what does NOT:** only the `.req.json` /
`.res.json` / `.meta.json` golden files carry over. The generated
`*_es_golden_test.go` **does not** — it was written against the OLD esclient API
(e.g. `TermQuery` took a raw value) and will not compile after Phase 1 merges
(now it needs a `FieldValue`). In 2.2 you **regenerate the test code** against the
new esclient API, **reusing the identical input cases** (same args per case), so
the only thing that changed between baseline and new is the library. Keep the
input cases in a shared, library-neutral table (or a comment block) so 2.2 can
reproduce them exactly.

## Phase 2.1 — CAPTURE (old branch, ES 6.x)

Per file:

1. Find call sites: `grep -nE 'esclient\.' <file>` and read each enclosing
   function. Identify every distinct query the function can emit.
2. Generate a `_es_golden_test.go` next to the file. Each test case:
   - constructs the inputs (table-driven; cover edge cases — see scope note),
   - calls the same code path that builds the query,
   - **serializes the generated query body to JSON** and writes it to
     `<case>.req.json`. (Old code: olivere builders implement `Source()` →
     `json.Marshal`. If the query is built inside `esclient`, add a tiny
     `esclient` debug hook that returns the marshaled body — do NOT change
     production behavior.)
3. Run the tests to emit all `.req.json` files.
4. Replay each request against the live ES 6.x to capture the response:
   ```
   scripts/replay.sh "$ES_URL" "$INDEX" <case>.req.json <case>.res.json <case>.meta.json
   ```
5. Commit `testdata/es-golden/**` as the immutable baseline. These files are the
   contract; the new code must satisfy them.

## Phase 2.2 — VERIFY (new branch, ES 9)

Preconditions: Phase 1 merged, `go build ./...` green, ES upgraded to 9 and
reachable, the SAME data/index available (restore the same snapshot if needed).

Per file:

1. Regenerate the request JSON the same way, writing `<case>.req.new.json`, and
   replay against ES 9 → `<case>.res.new.json`.
2. Compare:
   ```
   scripts/compare.sh <case>.req.json <case>.req.new.json    # query body
   scripts/compare.sh <case>.res.json <case>.res.new.json    # ES response
   ```
   `compare.sh` normalizes volatile fields (`took`, `_shards`, `_scroll_id`,
   score float jitter, hit order among equal scores) before diffing.
3. Classify each diff:
   - **Benign / version-expected** (do not "fix" the code) — known ES 6→9
     response-shape changes, listed in `references/known-benign-diffs.md`. If a
     diff is only in these fields, record it as accepted.
   - **Wrong** — the query *semantics* differ (different field, missing clause,
     value type changed, range bound flipped, agg renamed wrong). This means the
     Phase 1 mapping was incorrect.
4. For every "wrong" mismatch, invoke the **`es-query-equivalence`** skill to get
   the olivere↔esdsl difference for that construct, fix the `esclient` wrapper or
   the caller, rebuild (`go build ./...`), and re-run steps 1–2 until the diff is
   empty or fully classified benign.
5. A file passes Phase 2.2 when every case's request matches (modulo benign) and
   every response matches (modulo benign). Record pass/fail per case.

## Scripts (in this skill's `scripts/`)

- `replay.sh` — POST a request body to ES `_search`, save normalized response +
  meta. Works against 6.x and 9 (HTTP body search API).
- `normalize.jq` — strips/sorts volatile fields so diffs are meaningful.
- `compare.sh` — normalize both sides, structural diff, non-zero exit on real
  mismatch.

Read each script before running; pass `$ES_URL`/auth via env, never hardcode
secrets.

## Driving it

- `/es-golden-capture <file>` runs 2.1 for a file (dispatches `es-golden-runner`).
- `/es-golden-verify <file>` runs 2.2 for a file.

## References

- `references/known-benign-diffs.md` — ES 6→9 response differences that are NOT
  query bugs.
- For fixing "wrong" mismatches: the `es-query-equivalence` skill.
