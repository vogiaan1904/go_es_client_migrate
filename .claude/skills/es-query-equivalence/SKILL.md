---
name: es-query-equivalence
description: >-
  Authoritative knowledge of how olivere/elastic query, aggregation, and sort
  builders map to go-elasticsearch v9 esdsl, and the semantic gotchas where the
  two differ (term value wrapping, range type split, avg→average rename, sort
  enums, exists/minimum_should_match signatures). Use when a golden-master
  comparison shows a "wrong" request/response mismatch and you need to diagnose
  WHICH construct changed behavior and how to fix it. Triggers: "query JSON
  mismatch", "why is this clause different", "olivere vs esdsl difference".
---

# olivere ↔ esdsl Query Equivalence (diagnosis & fix knowledge)

Use this when Phase 2 verification (`es-golden-master`) reports a **wrong**
mismatch: the new code's generated query JSON differs from the golden in a way
that changes meaning. Your job is to find which construct's mapping was wrong and
correct the `esclient` wrapper or the caller.

## How to use it

1. Look at the diff `compare.sh` printed. Identify the JSON key that changed
   (`term`, `range`, `avg`, `bool.must`, `sort`, etc.).
2. Find that construct in the equivalence tables (full tables live in the
   reference below — do not duplicate them here).
3. Apply the documented difference. **Then confirm the fix against the
   compiler** (`go build ./...`) and re-run the golden comparison. The
   equivalence tables state intent; `go build` confirms the exact signature.

## The differences that actually cause wrong mismatches

These are the high-frequency culprits. Each maps a *symptom in the JSON diff* to
a *root cause and fix*:

| JSON symptom in the diff | Root cause | Fix |
|---|---|---|
| `"term":{"f":{"value":"true"}}` (string) where golden has `true` (bool) | `FieldValue` wrapped with the wrong helper | use `BoolVal`/`IntVal`/`FltVal`, not `StrVal`, in the `esclient.TermQuery` call |
| `range` uses `gt` where golden used `gte` (or number vs date serialization) | wrong range variant chosen (`Number`/`Date`/`Term`) or `Gt` vs `Gte` | match field mapping type and the original bound; see range section of the reference |
| in the REQUEST body, an agg serializes as `"average":{...}` where golden has `"avg":{...}` | esdsl's constructor is `NewAverageAggregation` but it must still emit the ES agg type `avg` — if it emits `average`, the wrong builder/type is in use | fix so the request emits `avg`; this is a request-body diff, NOT a response-key diff (the response key is your assigned name from `AddAggregation("myname",…)`, unaffected by the rename) |
| a `filter`/`must`/`should` clause is missing | esclient's own bool builder dropped a clause (e.g. empty-slice guard skipped it) | check the lazy `QueryCaster()` assembly applies every non-empty clause |
| `sort` direction flipped or field sort shape differs | `SortOrder` enum vs string, or sort-options wrapper shape | use the `sortorder` enum via the esclient sort helper; verify JSON shape |
| `exists`/`minimum_should_match` serialize wrong or won't build | doc's signatures are wrong (no-arg `NewExistsQuery`; variant-typed `MinimumShouldMatch`) | use the corrected forms; let `go build` confirm setter names |
| `terms` values order/typing differs | `TermsQuery` values each need a `FieldValue` of the right type | wrap each value with the matching helper |

## Authority reminder

The exact esdsl Go signatures are whatever `go-elasticsearch` exposes at the
version in `go.mod` — confirm by compiling, never by trusting prose. The
*equivalence intent* below is stable; the *syntax* is version-pinned.

## References

- `../esclient-wrapper-migrate/references/esclient-wrapper-migration.md` —
  Part 2 (full equivalence table), the "Key differences in esdsl syntax"
  section, and Part 6 (common mistakes → fixes). This is the single source;
  this skill is the diagnosis lens over it. Heed that doc's "code is
  illustrative" banner.
