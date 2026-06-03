# Known-benign ES 6.x → 9.x differences

These response/request differences are **expected consequences of the ES version
upgrade itself**, not bugs introduced by the olivere→esdsl migration. If a
golden diff is confined to these, classify it **benign** and accept it. Do NOT
change the Go code to "fix" them.

If a diff touches anything NOT on this list — a different field name, a missing
or extra query clause, a changed value or type, a flipped range bound, a wrong
aggregation — it is a **WRONG** mismatch: invoke the `es-query-equivalence`
skill and fix the wrapper/caller.

## Response-shape changes (benign)

| Area | ES 6.x | ES 7+/9.x | Why benign |
|---|---|---|---|
| `hits.total` | a bare number, e.g. `"total": 42` | an object `{"value":42,"relation":"eq"}` | Total-hits tracking changed in ES7; same count, new shape. The `esclient` result type already normalizes this to `Total.Value`. |
| `_type` in hits | present, e.g. `"_type":"doc"` | absent (mapping types removed) | Types were removed; their disappearance is expected. |
| `relation:"gte"` | n/a | may appear when `track_total_hits` defaults cap at 10000 | Set `track_total_hits: true` in BOTH capture and verify to make totals exact and comparable. |
| `took` | varies | varies | Latency; stripped by `normalize.jq`. |
| `_shards` | varies | varies | Cluster topology; stripped by `normalize.jq`. |
| `max_score` / `_score` | float | float (different scorer internals possible) | Relevance scores are not stable across versions; stripped by `normalize.jq`. Order among equal scores is re-sorted by `_id`. |

## Request-body differences — the cross-library serialization trap

**This is the most dangerous misclassification in the whole migration.** The
golden `.req.json` was serialized by **olivere's** `.Source()`; the new
`.req.new.json` is serialized by **esdsl's** marshaler. The two libraries encode
the *same logical query* with *different JSON forms*. These form differences are
**benign** and you must NOT change the esclient wrapper to make them match —
doing so corrupts correct code to mimic an old serializer artifact, which is the
exact harm this toolbox exists to prevent.

### The governing rule for request diffs

> A request-body diff is **WRONG** only if it is a **semantic** change:
> a different field, a clause added/removed (`must`/`filter`/`should`/`must_not`),
> a value or its *type* changed, a range bound moved (`gt`↔`gte`), a different
> range/agg variant, a different `size`/`from`/`sort`.
>
> A diff that preserves all of the above but differs in *encoding form* is
> **benign** — accept it. When unsure whether two forms are semantically equal,
> resolve it by sending BOTH bodies to the same ES and confirming identical hits,
> not by editing the wrapper.

| Benign form difference | Note |
|---|---|
| Key ordering | Irrelevant; `compare.sh` sorts keys. |
| Whitespace / formatting | Normalized by `jq`. |
| Short form vs object form | e.g. `{"match":{"f":"v"}}` vs `{"match":{"f":{"query":"v"}}}`, or `{"term":{"f":"v"}}` vs `{"term":{"f":{"value":"v"}}}`. Same query; libraries just pick different forms. Benign. |
| Default fields emitted by one side only | One library writes an explicit default (`boost:1.0`, `operator:"or"`, default `relation`) the other omits. Benign **iff** the emitted value is the documented default. |
| `1` vs `1.0` on a numeric field | int vs float encoding of the same magnitude. Benign. |
| Single-value vs single-element array | e.g. `"fields":"f"` vs `"fields":["f"]` where ES treats them identically. Benign. |

(The exact set of form differences between *your* olivere version and esdsl can
only be learned at runtime — apply the rule above, do not expect this list to be
exhaustive.)

## NOT benign (always investigate)

- Different field name targeted by a query/agg.
- A `must`/`filter`/`should`/`must_not` clause that appears on one side only.
- `term` value type changed (e.g. `"true"` string vs `true` boolean) — this is a
  real semantic change and a classic `FieldValue` wrapping bug.
- `range` bound moved between `gt/gte` or `lt/lte`, or number↔date↔term range
  variant chosen wrongly.
- Aggregation present under a different name (e.g. `avg` vs `average` key) or
  missing sub-aggregations.
- Different `size`/`from`/`sort` than the golden.

When unsure whether a diff is benign, treat it as WRONG until proven otherwise.
A false "benign" silently ships a behavior change; a false "wrong" only costs you
an investigation.
