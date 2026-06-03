---
name: esclient-wrapper-migrate
description: >-
  Migrate Go Elasticsearch code from olivere/elastic (v6/v7) to the esclient
  wrapper backed by the official go-elasticsearch v9 typed API. Use this when a
  Go file imports github.com/olivere/elastic, calls elastic.New*Query /
  elastic.New*Aggregation builders, or when replacing direct esdsl usage in
  handlers with esclient.* wrappers. Also use when designing or extending the
  esclient wrapper package itself (Phase 1 of the ES 6.x→9.x migration).
---

# esclient Wrapper Migration (Phase 1)

You are migrating a Go codebase off `olivere/elastic` onto an `esclient` wrapper
package backed by `go-elasticsearch/v9`. The end state: **handlers import only
`esclient`** and never see `olivere` or `esdsl`.

## PRIME DIRECTIVE — the compiler is the authority, not this skill

The reference material in `references/esclient-wrapper-migration.md` contains
mapping tables and example code. **The example code is illustrative, not
literal.** It was written ahead of compilation and several snippets do **not**
compile as written (see "Known-wrong patterns" below). Your job is NOT to
reproduce that code verbatim.

> **The ground truth is `go build ./...`.** A file is migrated when it builds,
> passes the grep gates, and its tests pass — not when it matches the doc.

If the doc's signature and the compiler disagree, **the compiler wins**, every
time. Discover the real esdsl signature the same way you would any unknown API:
write the call, run `go build`, read the error, adjust. Do not invent signatures
and do not trust the doc's signatures without compiling them.

## The architecture you MUST enforce (this part is non-negotiable)

These rules are the strict part of "architecture-strict". They do not depend on
any specific library version and must hold after every file you touch:

1. **Handlers/callers import only `esclient`.** Zero `olivere/elastic` imports.
   Zero `typedapi/esdsl` imports. Zero `typedapi/types` imports outside the
   `esclient` package.
2. **`esclient` owns every ES type and builder.** All query/aggregation/sort
   construction is exposed through `esclient.*` functions and builders.
3. **esdsl builders return *unexported* types, so you cannot re-export them
   directly.** This is the single most important fact for Phase 1:
   - Terminal queries → wrap as a function returning the marker interface, e.g.
     `func MatchQuery(field, value string) types.QueryVariant { return esdsl.NewMatchQuery(field, value) }`.
   - Compound/fluent builders (bool, dis_max, function_score, aggregations with
     chaining) → esclient defines its **own** builder struct that accumulates
     clauses and implements the marker interface (`QueryCaster() *types.Query`,
     etc.), assembling the esdsl object lazily. A thin pass-through that returns
     `*esdsl._boolQuery` is a compile error — it is impossible, not just
     discouraged.
4. **No ES library types leak through `esclient`'s public API.** `Search` takes
   an `esclient.SearchParams` and returns an `esclient.SearchResult`; callers
   never touch `res.Hits.Hits` raw shapes from the library.

## Known-wrong patterns in the reference doc (verified against v9.4.1)

Do **not** copy these from the doc — they fail to compile:

| Doc shows | Reality | Correct shape |
|---|---|---|
| `func BoolQuery() *esdsl._boolQuery` | `_boolQuery` is unexported; another package cannot name it | Own builder struct implementing `types.QueryVariant` |
| `type FieldValue = *esdsl._fieldValue` | unexported; alias is illegal | Use `types.FieldValueVariant`; provide `StrVal/IntVal/...` helpers |
| `esdsl.NewExistsQuery("f")` | constructor takes **no** args | `esdsl.NewExistsQuery().Field("f")` (verify the setter name via build) |
| `esdsl.NewFieldValue().Long(42)` | no `Long` method | confirm the real int setter via `go build` error before using |
| `.MinimumShouldMatch("2")` | wants a `MinimumShouldMatchVariant`, not a `string` | wrap the value; let the build error tell you the variant constructor |

Treat the doc's *mapping intent* (which olivere call maps to which esdsl
concept) as reliable; treat its *exact Go syntax* as unverified.

## Per-file workflow (run for each file, in order)

1. **Inventory.** `grep -nE 'elastic\.New|olivere' <file>` to list every olivere
   construct. Read the file to understand surrounding logic.
2. **Ensure the wrapper exists.** For every construct found, confirm an
   `esclient.*` wrapper exists. If not, add it to the `esclient` package first
   (terminal → interface-returning func; compound → own builder), then **build
   `esclient` alone** before touching the caller.
3. **Rewrite the caller** to use `esclient.*` only. Apply the mapping table in
   the reference doc as a guide, paying attention to the non-mechanical cases:
   - `TermQuery`/`TermsQuery` values must be wrapped (`StrVal/IntVal/...`).
   - `RangeQuery` splits by field type (number/date/term) — see Step 4 in the
     doc; when the field's mapping type is unknown, leave a `// TODO(es-migrate):
     confirm field type` and pick the most likely variant.
   - `FilterAggregation().Filter(q)` → query moves into the constructor.
   - `AvgAggregation` → `Average` rename.
   - sort, `TotalHits()`, `hit.Source` shape changes — see doc Parts 5–6.
4. **Remove the olivere import.**
5. **GATE — all must pass before the file is "done":**
   ```
   go build ./...                       # zero errors — the real authority
   go vet ./...                         # zero errors
   grep -nE 'olivere' <file>            # must be empty
   grep -nE 'typedapi/(esdsl|types)' <file>   # must be empty for handler files
   go test ./<pkg>/... -race            # must pass if tests exist
   ```
   If the build fails, read the error, fix against the compiler, repeat. Never
   declare a file done on a red build.

## Scope notes

- **Phase 1 only.** This skill migrates code so it compiles against ES 9's typed
  API. It does **not** prove runtime query equivalence — that is Phase 2
  (`es-golden-master` skill: capture golden request/response JSON on the old
  code, compare on the new). If a teammate asks "are the queries actually
  identical at runtime?", that's Phase 2, not here.
- **Branch discipline.** Phase 1 runs on a temp branch. Do not migrate on
  `main`; `main` must stay buildable against the old library until Phase 2.1
  golden capture is done.
- For driving the whole repo file-by-file, use the `/es-migrate` command, which
  dispatches the `es-migrator` subagent per file with these same gates.

## References

- `references/esclient-wrapper-migration.md` — full olivere↔esdsl mapping
  tables, wrapper package layout, handler before/after, step-by-step, common
  mistakes, checklist. **Read it for intent; verify all Go syntax against
  `go build`.**
