# esclient Wrapper Migration Reference
## Agent Instruction File — Read before touching any ES-related Go file

> ## ⚠️ READ THIS FIRST — code below is ILLUSTRATIVE, not literal
>
> This document was written before being compiled. The **mapping intent** (which
> olivere call corresponds to which esdsl concept) is reliable. The **exact Go
> syntax in the code blocks is NOT** — several snippets do not compile against
> `go-elasticsearch v9.4.1`. **`go build ./...` is the authority, not this doc.**
>
> Verified-wrong patterns (do not copy verbatim):
> - `func XxxQuery() *esdsl._xxxQuery` and `type FieldValue = *esdsl._fieldValue`
>   — esdsl builders return **unexported** types; another package **cannot name
>   them**. Terminal queries must be wrapped as functions returning the marker
>   interface (`types.QueryVariant`); compound builders (bool, etc.) need
>   esclient's **own** builder struct implementing `QueryCaster() *types.Query`.
> - `esdsl.NewExistsQuery("f")` — constructor takes **no** args (use a `.Field()`
>   setter; confirm the name via the build error).
> - `esdsl.NewFieldValue().Long(42)` — no `Long` method; confirm the real int
>   setter against the compiler.
> - `.MinimumShouldMatch("2")` — wants a `MinimumShouldMatchVariant`, not a
>   plain `string`.
>
> Use this file to know *what* to build and *which cases are non-mechanical*.
> Discover the *precise signatures* by compiling. See `../SKILL.md` § PRIME
> DIRECTIVE.

> **Scope:** This file covers two things:
> 1. How to migrate individual query builder calls (`elastic.NewMatchQuery` → your wrapper)
> 2. How the `esclient` wrapper package itself should be structured after migration
>
> **Rule:** Handlers must NEVER import `olivere/elastic` or `esdsl` directly.
> All ES types must come from the `esclient` package only.

---

## Part 1 — The Architecture Decision

### Problem you are solving

Before migration, the codebase has two patterns that both need fixing:

```
Pattern A — handler imports olivere directly:
  handler.go: import "github.com/olivere/elastic"
              elastic.NewMatchQuery(...)   ← BAD, breaks when olivere is removed

Pattern B — esclient wrapper hides the client, but not the query builders:
  esclient/client.go: uses olivere internally
  handler.go: uses esclient.Search(...) for execution
              but still calls elastic.NewBoolQuery() for building ← still BAD
```

### Target architecture

```
handler.go
  ↓  imports only
esclient/          ← single package that owns ALL ES types and operations
  client.go        ← connection, config, lifecycle
  query.go         ← re-exported query builder functions (the key new piece)
  search.go        ← search execution, result types
  bulk.go          ← bulk indexing
  index.go         ← index management
  types.go         ← re-exported types (Query, SearchHit, etc.)
  ↓  imports only
go-elasticsearch/v9/typedapi/esdsl   ← hidden from all other packages
go-elasticsearch/v9/typedapi/types
go-elasticsearch/v9
```

**Result:** Any handler file needs zero changes to its import list when the
underlying ES library changes again in the future. Only `esclient/` changes.

---

## Part 2 — Are olivere and esdsl query builders equivalent?

**Yes. The JSON they produce is identical for all standard query types.**

Both `olivere/elastic` and `go-elasticsearch/v9/typedapi/esdsl` are Go DSL
wrappers that serialize to the same Elasticsearch JSON query DSL. The wire
protocol is what matters, and both produce identical JSON for the same
logical query.

Proof from official docs: "Both approaches produce identical JSON and share
the same typed API transport. You can freely mix them in the same application."
— elastic.co/docs/reference/elasticsearch/clients/go/typed-api/esdsl

### Query builder equivalence table (complete)

| olivere v6 call | esdsl v9 call | JSON produced | Safe? |
|---|---|---|---|
| `elastic.NewMatchAllQuery()` | `esdsl.NewMatchAllQuery()` | `{"match_all":{}}` | ✅ identical |
| `elastic.NewMatchQuery("f","v")` | `esdsl.NewMatchQuery("f","v")` | `{"match":{"f":{"query":"v"}}}` | ✅ identical |
| `elastic.NewMatchPhraseQuery("f","v")` | `esdsl.NewMatchPhraseQuery("f","v")` | `{"match_phrase":{"f":{"query":"v"}}}` | ✅ identical |
| `elastic.NewMultiMatchQuery("v","f1","f2")` | `esdsl.NewMultiMatchQuery("v","f1","f2")` | `{"multi_match":{"query":"v","fields":["f1","f2"]}}` | ✅ identical |
| `elastic.NewTermQuery("f","v")` | `esdsl.NewTermQuery("f", esdsl.NewFieldValue().String("v"))` | `{"term":{"f":{"value":"v"}}}` | ✅ identical |
| `elastic.NewTermsQuery("f","v1","v2")` | `esdsl.NewTermsQuery("f", esdsl.NewFieldValue().String("v1"), esdsl.NewFieldValue().String("v2"))` | `{"terms":{"f":["v1","v2"]}}` | ✅ identical |
| `elastic.NewBoolQuery()` | `esdsl.NewBoolQuery()` | `{"bool":{}}` | ✅ identical |
| `.Must(q1,q2)` | `.Must(q1,q2)` | `"must":[...]` | ✅ identical |
| `.Filter(q1)` | `.Filter(q1)` | `"filter":[...]` | ✅ identical |
| `.Should(q1)` | `.Should(q1)` | `"should":[...]` | ✅ identical |
| `.MustNot(q1)` | `.MustNot(q1)` | `"must_not":[...]` | ✅ identical |
| `.MinimumShouldMatch("2")` | `.MinimumShouldMatch("2")` | `"minimum_should_match":"2"` | ✅ identical |
| `elastic.NewRangeQuery("f").Gte(v).Lte(v)` | `esdsl.NewNumberRangeQuery("f").Gte(v).Lte(v)` | `{"range":{"f":{"gte":v,"lte":v}}}` | ✅ identical |
| `elastic.NewRangeQuery("f").From(t).To(t)` | `esdsl.NewDateRangeQuery("f").From(str).To(str)` | `{"range":{"f":{"from":...,"to":...}}}` | ✅ identical |
| `elastic.NewExistsQuery("f")` | `esdsl.NewExistsQuery("f")` | `{"exists":{"field":"f"}}` | ✅ identical |
| `elastic.NewPrefixQuery("f","v")` | `esdsl.NewPrefixQuery("f","v")` | `{"prefix":{"f":{"value":"v"}}}` | ✅ identical |
| `elastic.NewWildcardQuery("f","v*")` | `esdsl.NewWildcardQuery("f","v*")` | `{"wildcard":{"f":{"value":"v*"}}}` | ✅ identical |
| `elastic.NewFuzzyQuery("f","v")` | `esdsl.NewFuzzyQuery("f","v")` | `{"fuzzy":{"f":{"value":"v"}}}` | ✅ identical |
| `elastic.NewQueryStringQuery("q str")` | `esdsl.NewQueryStringQuery("q str")` | `{"query_string":{"query":"q str"}}` | ✅ identical |
| `elastic.NewNestedQuery("path",q)` | `esdsl.NewNestedQuery("path",q)` | `{"nested":{"path":"path","query":{...}}}` | ✅ identical |
| `elastic.NewHasChildQuery("type",q)` | `esdsl.NewHasChildQuery("type",q)` | `{"has_child":{"type":"type","query":{...}}}` | ✅ identical |
| `elastic.NewGeoDistanceQuery("f").Point(lat,lon).Distance("10km")` | `esdsl.NewGeoDistanceQuery("f").Location(...).Distance("10km")` | `{"geo_distance":{...}}` | ✅ identical |
| `elastic.NewIdsQuery().Ids("1","2")` | `esdsl.NewIdsQuery().Values("1","2")` | `{"ids":{"values":["1","2"]}}` | ✅ identical |
| `elastic.NewMatchNoneQuery()` | `esdsl.NewMatchNoneQuery()` | `{"match_none":{}}` | ✅ identical |
| `elastic.NewConstantScoreQuery(q)` | `esdsl.NewConstantScoreQuery(q)` | `{"constant_score":{"filter":{...}}}` | ✅ identical |
| `elastic.NewDisMaxQuery()` | `esdsl.NewDisMaxQuery()` | `{"dis_max":{"queries":[]}}` | ✅ identical |
| `elastic.NewFunctionScoreQuery()` | `esdsl.NewFunctionScoreQuery()` | `{"function_score":{}}` | ✅ identical |
| `elastic.NewSpanTermQuery("f","v")` | `esdsl.NewSpanTermQuery("f","v")` | `{"span_term":{"f":{"value":"v"}}}` | ✅ identical |
| `elastic.NewTermsAggregation().Field("f")` | `esdsl.NewTermsAggregation().Field("f")` | `{"terms":{"field":"f"}}` | ✅ identical |
| `elastic.NewDateHistogramAggregation().Field("f")` | `esdsl.NewDateHistogramAggregation().Field("f")` | `{"date_histogram":{"field":"f"}}` | ✅ identical |
| `elastic.NewAvgAggregation().Field("f")` | `esdsl.NewAverageAggregation().Field("f")` | `{"avg":{"field":"f"}}` | ⚠️ renamed |
| `elastic.NewSumAggregation().Field("f")` | `esdsl.NewSumAggregation().Field("f")` | `{"sum":{"field":"f"}}` | ✅ identical |
| `elastic.NewMinAggregation().Field("f")` | `esdsl.NewMinAggregation().Field("f")` | `{"min":{"field":"f"}}` | ✅ identical |
| `elastic.NewMaxAggregation().Field("f")` | `esdsl.NewMaxAggregation().Field("f")` | `{"max":{"field":"f"}}` | ✅ identical |
| `elastic.NewFilterAggregation().Filter(q)` | `esdsl.NewFilterAggregation(q)` | `{"filter":{...}}` | ✅ identical |
| `elastic.NewNestedAggregation().Path("p")` | `esdsl.NewNestedAggregation().Path("p")` | `{"nested":{"path":"p"}}` | ✅ identical |
| `elastic.NewValueCountAggregation().Field("f")` | `esdsl.NewValueCountAggregation().Field("f")` | `{"value_count":{"field":"f"}}` | ✅ identical |
| `elastic.NewCardinalityAggregation().Field("f")` | `esdsl.NewCardinalityAggregation().Field("f")` | `{"cardinality":{"field":"f"}}` | ✅ identical |

### Key differences in esdsl syntax (not just rename)

**1. TermQuery value must be wrapped:**
```go
// olivere — raw value, any type
elastic.NewTermQuery("status", "active")
elastic.NewTermQuery("count", 42)

// esdsl — must use FieldValue wrapper
esdsl.NewTermQuery("status", esdsl.NewFieldValue().String("active"))
esdsl.NewTermQuery("count",  esdsl.NewFieldValue().Long(42))

// FieldValue helpers:
//   .String(s string)
//   .Long(i int64)
//   .Double(f float64)
//   .Bool(b bool)
```

**2. RangeQuery splits into typed variants:**
```go
// olivere — single type for all ranges
elastic.NewRangeQuery("price").Gte(100).Lte(500)
elastic.NewRangeQuery("created").Gte("2024-01-01")

// esdsl — pick the right constructor
esdsl.NewNumberRangeQuery("price").Gte(100).Lte(500)
esdsl.NewDateRangeQuery("created").Gte("2024-01-01")
esdsl.NewTermRangeQuery("name").Gte("a").Lte("m")
// Use Gte/Lte for closed, Gt/Lt for open bounds — same as olivere
```

**3. AvgAggregation renamed:**
```go
elastic.NewAvgAggregation()     // olivere
esdsl.NewAverageAggregation()  // esdsl — "Average" not "Avg"
```

**4. AddAggregation pattern:**
```go
// olivere — chained on search service
client.Search().Aggregation("name", agg)

// esdsl — method on typed search
es.Search().AddAggregation("name", esdsl.NewTermsAggregation().Field("f"))
```

**5. SortOrder is a typed enum:**
```go
// olivere
elastic.NewFieldSort("price").Desc()

// esdsl
import "github.com/elastic/go-elasticsearch/v9/typedapi/types/enums/sortorder"
esdsl.NewFieldSort(sortorder.Desc)
// OR via wrapper: esclient.SortDesc, esclient.SortAsc (see Part 3)
```

---

## Part 3 — The `esclient` Wrapper Package Design

### File structure to build

```
esclient/
  client.go    — Client struct, New(), Close(), connection config
  query.go     — All query builder wrappers (the main new file)
  search.go    — Search(), SearchResult, SearchHit types
  bulk.go      — Bulk(), BulkItem
  index.go     — CreateIndex(), DeleteIndex(), IndexExists()
  types.go     — Shared type aliases and re-exports
```

### `esclient/types.go` — type re-exports

```go
package esclient

import (
    "github.com/elastic/go-elasticsearch/v9/typedapi/esdsl"
    "github.com/elastic/go-elasticsearch/v9/typedapi/types"
    "github.com/elastic/go-elasticsearch/v9/typedapi/types/enums/sortorder"
)

// Query is the type that all query builders satisfy.
// Handlers use this type — never import types.QueryVariant directly.
type Query = types.QueryVariant

// Aggregation is the type all aggregation builders satisfy.
type Aggregation = types.AggregationsVariant

// SortOption is the type for sort builders.
type SortOption = types.SortOptionsVariant

// SearchHit is a single result hit.
type SearchHit = types.Hit[json.RawMessage]

// TotalHits holds the total count and whether it's exact.
type TotalHits struct {
    Value    int64
    Relation string // "eq" = exact, "gte" = lower bound
}

// Sort direction constants — handlers use these, not sortorder package.
const (
    SortAsc  = sortorder.Asc
    SortDesc = sortorder.Desc
)

// FieldValue wraps a term value. Avoids handlers importing esdsl.
type FieldValue = *esdsl._fieldValue  // use via esclient.StrVal, esclient.IntVal etc.

// Convenience constructors for FieldValue.
func StrVal(s string) types.FieldValue  { return esdsl.NewFieldValue().String(s) }
func IntVal(i int64)  types.FieldValue  { return esdsl.NewFieldValue().Long(i) }
func FltVal(f float64) types.FieldValue { return esdsl.NewFieldValue().Double(f) }
func BoolVal(b bool)  types.FieldValue  { return esdsl.NewFieldValue().Bool(b) }
```

### `esclient/query.go` — complete wrapper functions

This is the key file. Every function here is a thin wrapper that re-exports
an esdsl builder. Handlers call `esclient.MatchQuery(...)`, never `esdsl.NewMatchQuery(...)`.

```go
package esclient

import (
    "github.com/elastic/go-elasticsearch/v9/typedapi/esdsl"
    "github.com/elastic/go-elasticsearch/v9/typedapi/types"
)

// ─────────────────────────────────────────────────────────
// Full-text queries
// ─────────────────────────────────────────────────────────

// MatchAllQuery matches every document.
// olivere: elastic.NewMatchAllQuery()
func MatchAllQuery() types.QueryVariant {
    return esdsl.NewMatchAllQuery()
}

// MatchNoneQuery matches no documents.
// olivere: elastic.NewMatchNoneQuery()
func MatchNoneQuery() types.QueryVariant {
    return esdsl.NewMatchNoneQuery()
}

// MatchQuery performs full-text search on field with value.
// olivere: elastic.NewMatchQuery(field, value)
func MatchQuery(field string, value interface{}) *esdsl._matchQuery {
    return esdsl.NewMatchQuery(field, value)
}

// MatchPhraseQuery matches an exact phrase.
// olivere: elastic.NewMatchPhraseQuery(field, value)
func MatchPhraseQuery(field, value string) *esdsl._matchPhraseQuery {
    return esdsl.NewMatchPhraseQuery(field, value)
}

// MatchPhrasePrefixQuery matches a phrase prefix.
// olivere: elastic.NewMatchPhrasePrefixQuery(field, value)
func MatchPhrasePrefixQuery(field, value string) *esdsl._matchPhrasePrefixQuery {
    return esdsl.NewMatchPhrasePrefixQuery(field, value)
}

// MultiMatchQuery searches value across multiple fields.
// olivere: elastic.NewMultiMatchQuery(value, fields...)
func MultiMatchQuery(value string, fields ...string) *esdsl._multiMatchQuery {
    return esdsl.NewMultiMatchQuery(value, fields...)
}

// QueryStringQuery uses Lucene query syntax.
// olivere: elastic.NewQueryStringQuery(query)
func QueryStringQuery(query string) *esdsl._queryStringQuery {
    return esdsl.NewQueryStringQuery(query)
}

// SimpleQueryStringQuery is a safer subset of query_string.
// olivere: elastic.NewSimpleQueryStringQuery(query)
func SimpleQueryStringQuery(query string) *esdsl._simpleQueryStringQuery {
    return esdsl.NewSimpleQueryStringQuery(query)
}

// ─────────────────────────────────────────────────────────
// Term-level queries
// ─────────────────────────────────────────────────────────

// TermQuery performs exact value matching on a field.
// olivere: elastic.NewTermQuery(field, value)
// NOTE: value must be wrapped — use StrVal(), IntVal(), FltVal(), BoolVal().
func TermQuery(field string, value types.FieldValue) *esdsl._termQuery {
    return esdsl.NewTermQuery(field, value)
}

// TermsQuery matches any of the given values (OR).
// olivere: elastic.NewTermsQuery(field, values...)
func TermsQuery(field string, values ...types.FieldValue) *esdsl._termsQuery {
    return esdsl.NewTermsQuery(field, values...)
}

// ExistsQuery matches documents where the field exists.
// olivere: elastic.NewExistsQuery(field)
func ExistsQuery(field string) *esdsl._existsQuery {
    return esdsl.NewExistsQuery(field)
}

// IdsQuery matches documents by their _id.
// olivere: elastic.NewIdsQuery().Ids("1","2")
func IdsQuery() *esdsl._idsQuery {
    return esdsl.NewIdsQuery()
}

// PrefixQuery matches documents where field starts with prefix.
// olivere: elastic.NewPrefixQuery(field, prefix)
func PrefixQuery(field, prefix string) *esdsl._prefixQuery {
    return esdsl.NewPrefixQuery(field, prefix)
}

// WildcardQuery matches documents where field matches pattern (* and ?).
// olivere: elastic.NewWildcardQuery(field, pattern)
func WildcardQuery(field, pattern string) *esdsl._wildcardQuery {
    return esdsl.NewWildcardQuery(field, pattern)
}

// RegexpQuery matches documents where field matches regexp.
// olivere: elastic.NewRegexpQuery(field, regexp)
func RegexpQuery(field, regexp string) *esdsl._regexpQuery {
    return esdsl.NewRegexpQuery(field, regexp)
}

// FuzzyQuery matches documents with values similar to the search term.
// olivere: elastic.NewFuzzyQuery(field, value)
func FuzzyQuery(field, value string) *esdsl._fuzzyQuery {
    return esdsl.NewFuzzyQuery(field, value)
}

// ─────────────────────────────────────────────────────────
// Range queries — IMPORTANT: type-specific in esdsl
// ─────────────────────────────────────────────────────────

// NumberRangeQuery matches documents with numeric field in range.
// olivere: elastic.NewRangeQuery(field) for numeric fields
// Chain: .Gte(n).Lte(n).Gt(n).Lt(n)
func NumberRangeQuery(field string) *esdsl._numberRangeQuery {
    return esdsl.NewNumberRangeQuery(field)
}

// DateRangeQuery matches documents with date field in range.
// olivere: elastic.NewRangeQuery(field) for date fields
// Values as strings: "2024-01-01" or "now-1d/d"
func DateRangeQuery(field string) *esdsl._dateRangeQuery {
    return esdsl.NewDateRangeQuery(field)
}

// TermRangeQuery matches documents with keyword/text field in range.
// olivere: elastic.NewRangeQuery(field) for string fields
func TermRangeQuery(field string) *esdsl._termRangeQuery {
    return esdsl.NewTermRangeQuery(field)
}

// ─────────────────────────────────────────────────────────
// Compound queries
// ─────────────────────────────────────────────────────────

// BoolQuery combines multiple queries with boolean logic.
// olivere: elastic.NewBoolQuery()
// Chain: .Must(q...).Filter(q...).Should(q...).MustNot(q...)
//        .MinimumShouldMatch("1")
func BoolQuery() *esdsl._boolQuery {
    return esdsl.NewBoolQuery()
}

// ConstantScoreQuery wraps a filter query and gives all matches a fixed score.
// olivere: elastic.NewConstantScoreQuery(filter)
func ConstantScoreQuery(filter types.QueryVariant) *esdsl._constantScoreQuery {
    return esdsl.NewConstantScoreQuery(filter)
}

// DisMaxQuery returns the maximum score of its subqueries.
// olivere: elastic.NewDisMaxQuery()
func DisMaxQuery() *esdsl._disMaxQuery {
    return esdsl.NewDisMaxQuery()
}

// FunctionScoreQuery modifies scores using score functions.
// olivere: elastic.NewFunctionScoreQuery()
func FunctionScoreQuery() *esdsl._functionScoreQuery {
    return esdsl.NewFunctionScoreQuery()
}

// BoostingQuery returns documents matching positive; demotes matches for negative.
// olivere: elastic.NewBoostingQuery()
func BoostingQuery(negative types.QueryVariant, negativeBoost float64) *esdsl._boostingQuery {
    return esdsl.NewBoostingQuery(negative, negativeBoost)
}

// ─────────────────────────────────────────────────────────
// Joining queries
// ─────────────────────────────────────────────────────────

// NestedQuery searches within a nested object field.
// olivere: elastic.NewNestedQuery(path, query)
func NestedQuery(path string, query types.QueryVariant) *esdsl._nestedQuery {
    return esdsl.NewNestedQuery(path, query)
}

// HasChildQuery matches parents that have matching children (join field).
// olivere: elastic.NewHasChildQuery(type, query)
func HasChildQuery(childType string, query types.QueryVariant) *esdsl._hasChildQuery {
    return esdsl.NewHasChildQuery(childType, query)
}

// HasParentQuery matches children whose parent matches (join field).
// olivere: elastic.NewHasParentQuery(parentType, query)
func HasParentQuery(parentType string, query types.QueryVariant) *esdsl._hasParentQuery {
    return esdsl.NewHasParentQuery(parentType, query)
}

// ─────────────────────────────────────────────────────────
// Geo queries
// ─────────────────────────────────────────────────────────

// GeoDistanceQuery matches documents within distance from a point.
// olivere: elastic.NewGeoDistanceQuery(field).Point(lat,lon).Distance("10km")
func GeoDistanceQuery(field string) *esdsl._geoDistanceQuery {
    return esdsl.NewGeoDistanceQuery(field)
}

// GeoBoundingBoxQuery matches documents in a bounding box.
// olivere: elastic.NewGeoBoundingBoxQuery(field)
func GeoBoundingBoxQuery(field string) *esdsl._geoBoundingBoxQuery {
    return esdsl.NewGeoBoundingBoxQuery(field)
}

// ─────────────────────────────────────────────────────────
// Aggregations
// ─────────────────────────────────────────────────────────

// TermsAgg groups documents by field values (bucket aggregation).
// olivere: elastic.NewTermsAggregation().Field(f).Size(n)
func TermsAgg() *esdsl._termsAggregation {
    return esdsl.NewTermsAggregation()
}

// DateHistogramAgg groups documents by date intervals.
// olivere: elastic.NewDateHistogramAggregation().Field(f).CalendarInterval("day")
func DateHistogramAgg() *esdsl._dateHistogramAggregation {
    return esdsl.NewDateHistogramAggregation()
}

// HistogramAgg groups documents by numeric intervals.
// olivere: elastic.NewHistogramAggregation().Field(f).Interval(100)
func HistogramAgg() *esdsl._histogramAggregation {
    return esdsl.NewHistogramAggregation()
}

// FilterAgg applies a single query filter as a bucket.
// olivere: elastic.NewFilterAggregation().Filter(q)
func FilterAgg(query types.QueryVariant) *esdsl._filterAggregation {
    return esdsl.NewFilterAggregation(query)
}

// NestedAgg navigates into nested documents for aggregation.
// olivere: elastic.NewNestedAggregation().Path("p")
func NestedAgg() *esdsl._nestedAggregation {
    return esdsl.NewNestedAggregation()
}

// AvgAgg computes average of a numeric field.
// olivere: elastic.NewAvgAggregation().Field(f)
// NOTE: renamed from Avg → Average in esdsl.
func AvgAgg() *esdsl._averageAggregation {
    return esdsl.NewAverageAggregation()
}

// SumAgg computes sum of a numeric field.
// olivere: elastic.NewSumAggregation().Field(f)
func SumAgg() *esdsl._sumAggregation {
    return esdsl.NewSumAggregation()
}

// MinAgg computes minimum value of a field.
func MinAgg() *esdsl._minAggregation {
    return esdsl.NewMinAggregation()
}

// MaxAgg computes maximum value of a field.
func MaxAgg() *esdsl._maxAggregation {
    return esdsl.NewMaxAggregation()
}

// CountAgg counts values of a field (value_count aggregation).
func CountAgg() *esdsl._valueCountAggregation {
    return esdsl.NewValueCountAggregation()
}

// CardinalityAgg counts distinct values of a field.
func CardinalityAgg() *esdsl._cardinalityAggregation {
    return esdsl.NewCardinalityAggregation()
}

// ─────────────────────────────────────────────────────────
// Sort helpers
// ─────────────────────────────────────────────────────────

// SortByField returns a field sort option.
// Usage: esclient.SortByField("price", esclient.SortDesc)
// olivere: elastic.NewFieldSort("price").Desc()
func SortByField(field string, order sortorder.SortOrder) *esdsl._sortOptions {
    return esdsl.NewSortOptions().AddSortOption(field, esdsl.NewFieldSort(order))
}

// SortByScore sorts by relevance score descending (default ES behavior).
// olivere: elastic.NewScoreSort()
func SortByScore() *esdsl._sortOptions {
    return esdsl.NewSortOptions().AddSortOption("_score", esdsl.NewFieldSort(sortorder.Desc))
}
```

### `esclient/search.go` — search execution + result types

```go
package esclient

import (
    "context"
    "encoding/json"

    elasticsearch "github.com/elastic/go-elasticsearch/v9"
    "github.com/elastic/go-elasticsearch/v9/typedapi/esdsl"
    "github.com/elastic/go-elasticsearch/v9/typedapi/types"
)

// SearchResult is what handlers receive — no ES library types leak out.
type SearchResult struct {
    Total    TotalHits
    Hits     []SearchHit
    MaxScore *float64
    // Aggregations are kept as raw for flexibility; use ParseAgg helpers.
    Aggs     map[string]types.Aggregate
}

// SearchParams is what handlers pass in — no ES library types leak out.
type SearchParams struct {
    Index    []string
    Query    types.QueryVariant          // built via esclient.MatchQuery() etc.
    Aggs     map[string]types.AggregationsVariant  // built via esclient.TermsAgg() etc.
    Sort     []types.SortOptionsVariant
    From     int
    Size     int
    Source   []string // fields to include; nil = all
}

// Search executes a search and returns a clean SearchResult.
// Handlers never touch the raw ES response.
func (c *Client) Search(ctx context.Context, p SearchParams) (*SearchResult, error) {
    req := c.typed.Search().Index(p.Index...)

    if p.Query != nil {
        req = req.Query(p.Query)
    }
    for name, agg := range p.Aggs {
        req = req.AddAggregation(name, agg)
    }
    for _, s := range p.Sort {
        req = req.Sort(s)
    }
    if p.Size > 0 {
        req = req.Size(p.Size)
    }
    if p.From > 0 {
        req = req.From(p.From)
    }

    res, err := req.Do(ctx)
    if err != nil {
        return nil, fmt.Errorf("esclient.Search: %w", err)
    }

    result := &SearchResult{
        Total: TotalHits{
            Value:    res.Hits.Total.Value,
            Relation: string(res.Hits.Total.Relation),
        },
        Hits:  res.Hits.Hits,
        Aggs:  res.Aggregations,
    }
    if res.Hits.MaxScore != nil {
        result.MaxScore = res.Hits.MaxScore
    }
    return result, nil
}
```

---

## Part 4 — Handler Migration Pattern

### Before (handler imports olivere directly)

```go
// handlers/product_handler.go — BEFORE
import (
    "github.com/olivere/elastic"          // ← REMOVE THIS
    "myapp/esclient"
)

func (h *Handler) SearchProducts(ctx context.Context, req SearchReq) ([]Product, error) {
    q := elastic.NewBoolQuery().                    // ← uses olivere directly
        Must(elastic.NewMatchQuery("name", req.Q)).
        Filter(elastic.NewTermQuery("active", true))

    result, err := h.es.Search(ctx, esclient.SearchParams{
        Index: []string{"products"},
        Query: q,
        Size:  req.Limit,
    })
    // ...
}
```

### After (handler uses esclient wrappers only)

```go
// handlers/product_handler.go — AFTER
import (
    // NO olivere import
    // NO esdsl import
    "myapp/esclient"                      // ← only this
)

func (h *Handler) SearchProducts(ctx context.Context, req SearchReq) ([]Product, error) {
    q := esclient.BoolQuery().                      // ← uses esclient wrapper
        Must(esclient.MatchQuery("name", req.Q)).
        Filter(esclient.TermQuery("active", esclient.BoolVal(true)))

    result, err := h.es.Search(ctx, esclient.SearchParams{
        Index: []string{"products"},
        Query: q,
        Size:  req.Limit,
    })
    // ...
}
```

---

## Part 5 — Step-by-Step Migration Instructions for Agent

When you encounter a file that imports `github.com/olivere/elastic`:

### Step 1: Identify all olivere usages

```bash
grep -n "elastic\." <file>.go | grep -v "esclient\."
```

### Step 2: Replace query builders — mechanical substitution

Apply these replacements IN ORDER (more specific first):

| Find | Replace with | Notes |
|---|---|---|
| `elastic.NewMatchAllQuery()` | `esclient.MatchAllQuery()` | direct |
| `elastic.NewMatchNoneQuery()` | `esclient.MatchNoneQuery()` | direct |
| `elastic.NewMatchQuery(` | `esclient.MatchQuery(` | direct |
| `elastic.NewMatchPhraseQuery(` | `esclient.MatchPhraseQuery(` | direct |
| `elastic.NewMatchPhrasePrefixQuery(` | `esclient.MatchPhrasePrefixQuery(` | direct |
| `elastic.NewMultiMatchQuery(` | `esclient.MultiMatchQuery(` | direct |
| `elastic.NewQueryStringQuery(` | `esclient.QueryStringQuery(` | direct |
| `elastic.NewSimpleQueryStringQuery(` | `esclient.SimpleQueryStringQuery(` | direct |
| `elastic.NewBoolQuery()` | `esclient.BoolQuery()` | direct |
| `elastic.NewExistsQuery(` | `esclient.ExistsQuery(` | direct |
| `elastic.NewIdsQuery()` | `esclient.IdsQuery()` | direct |
| `elastic.NewPrefixQuery(` | `esclient.PrefixQuery(` | direct |
| `elastic.NewWildcardQuery(` | `esclient.WildcardQuery(` | direct |
| `elastic.NewRegexpQuery(` | `esclient.RegexpQuery(` | direct |
| `elastic.NewFuzzyQuery(` | `esclient.FuzzyQuery(` | direct |
| `elastic.NewConstantScoreQuery(` | `esclient.ConstantScoreQuery(` | direct |
| `elastic.NewDisMaxQuery()` | `esclient.DisMaxQuery()` | direct |
| `elastic.NewFunctionScoreQuery()` | `esclient.FunctionScoreQuery()` | direct |
| `elastic.NewNestedQuery(` | `esclient.NestedQuery(` | direct |
| `elastic.NewHasChildQuery(` | `esclient.HasChildQuery(` | direct |
| `elastic.NewHasParentQuery(` | `esclient.HasParentQuery(` | direct |
| `elastic.NewGeoDistanceQuery(` | `esclient.GeoDistanceQuery(` | direct |
| `elastic.NewGeoBoundingBoxQuery(` | `esclient.GeoBoundingBoxQuery(` | direct |
| `elastic.NewTermsAggregation()` | `esclient.TermsAgg()` | direct |
| `elastic.NewDateHistogramAggregation()` | `esclient.DateHistogramAgg()` | direct |
| `elastic.NewHistogramAggregation()` | `esclient.HistogramAgg()` | direct |
| `elastic.NewFilterAggregation()` | `esclient.FilterAgg(` — needs query arg | check .Filter() chain |
| `elastic.NewNestedAggregation()` | `esclient.NestedAgg()` | direct |
| `elastic.NewAvgAggregation()` | `esclient.AvgAgg()` | renamed |
| `elastic.NewSumAggregation()` | `esclient.SumAgg()` | direct |
| `elastic.NewMinAggregation()` | `esclient.MinAgg()` | direct |
| `elastic.NewMaxAggregation()` | `esclient.MaxAgg()` | direct |
| `elastic.NewValueCountAggregation()` | `esclient.CountAgg()` | direct |
| `elastic.NewCardinalityAggregation()` | `esclient.CardinalityAgg()` | direct |

### Step 3: Fix TermQuery values (requires manual attention)

```bash
grep -n "NewTermQuery\|NewTermsQuery" <file>.go
```

For each occurrence, wrap the value argument:
- string → `esclient.StrVal("value")`
- int/int64 → `esclient.IntVal(42)`
- float64 → `esclient.FltVal(3.14)`
- bool → `esclient.BoolVal(true)`

### Step 4: Fix RangeQuery (requires field type knowledge)

```bash
grep -n "NewRangeQuery" <file>.go
```

For each:
- Numeric fields → `esclient.NumberRangeQuery("field")`
- Date fields → `esclient.DateRangeQuery("field")`
- String/keyword fields → `esclient.TermRangeQuery("field")`

When in doubt, check the index mapping. If unknown, use `DateRangeQuery` for
timestamp fields, `NumberRangeQuery` for price/count/score fields.

### Step 5: Fix sort calls

```bash
grep -n "NewFieldSort\|NewScoreSort\|SortBy\|\.Sort(" <file>.go
```

- `elastic.NewFieldSort("f").Asc()` → `esclient.SortByField("f", esclient.SortAsc)`
- `elastic.NewFieldSort("f").Desc()` → `esclient.SortByField("f", esclient.SortDesc)`
- `elastic.NewScoreSort()` → `esclient.SortByScore()`

### Step 6: Fix FilterAggregation (special case)

```go
// BEFORE — chain style
elastic.NewFilterAggregation().Filter(myQuery)

// AFTER — query goes in constructor
esclient.FilterAgg(myQuery)
```

### Step 7: Remove olivere import

```go
// Remove this line:
"github.com/olivere/elastic"
"gopkg.in/olivere/elastic.v6"
"github.com/olivere/elastic/v7"

// Ensure this is present:
"myapp/esclient"
```

### Step 8: Validate

```bash
go build ./...                   # must pass with zero errors
grep -n "olivere" <file>.go      # must be empty
grep -n '"github.com/elastic/go-elasticsearch' <file>.go  # must be empty (handler only uses esclient)
go test ./<package>/... -race    # must pass
```

---

## Part 6 — Common Migration Mistakes and Fixes

| Mistake | Symptom | Fix |
|---|---|---|
| `elastic.NewTermQuery("f", "v")` not updated | compile error: cannot use string as FieldValue | Wrap: `esclient.TermQuery("f", esclient.StrVal("v"))` |
| `elastic.NewRangeQuery("price").Gte(100)` left as-is | compile error or type mismatch | Change to `esclient.NumberRangeQuery("price").Gte(100)` |
| `elastic.NewAvgAggregation()` not renamed | compile error: undefined | Change to `esclient.AvgAgg()` |
| `elastic.NewFilterAggregation().Filter(q)` syntax kept | compile error: too many args or wrong type | Change to `esclient.FilterAgg(q)` — query is constructor arg |
| Handler still imports `esdsl` directly | handler is still library-coupled | Move to using `esclient.*` wrappers only |
| `hit.Source` dereferenced as `*json.RawMessage` | compile error: `hit.Source_` is not a pointer | Change to `hit.Source_` (no `*`, no pointer dereference) |
| `res.TotalHits()` called as method | compile error: no method | Change to `res.Total.Value` |
| `elastic.IsNotFound(err)` | compile error: no such function | Use `esclient.IsNotFound(err)` — add this helper to esclient |

### Add this to `esclient/client.go`:

```go
// IsNotFound returns true if the error is a 404 Not Found from Elasticsearch.
// olivere: elastic.IsNotFound(err)
func IsNotFound(err error) bool {
    if err == nil {
        return false
    }
    var apiErr *types.ElasticsearchError
    return errors.As(err, &apiErr) && apiErr.Status == 404
}

// IsConflict returns true if the error is a 409 Conflict.
// olivere: elastic.IsConflict(err)
func IsConflict(err error) bool {
    var apiErr *types.ElasticsearchError
    return errors.As(err, &apiErr) && apiErr.Status == 409
}
```

---

## Part 7 — Checklist: Is the wrapper safe and complete?

Before declaring a file migrated, verify:

- [ ] Zero `olivere` imports in file
- [ ] Zero direct `esdsl` imports in handler files (only in `esclient/`)
- [ ] All `elastic.New*Query(` calls replaced with `esclient.*Query(`
- [ ] All `elastic.New*Aggregation(` calls replaced with `esclient.*Agg(`
- [ ] `NewTermQuery` / `NewTermsQuery` values wrapped with `StrVal/IntVal/FltVal/BoolVal`
- [ ] `NewRangeQuery` replaced with type-appropriate `NumberRangeQuery/DateRangeQuery/TermRangeQuery`
- [ ] `NewAvgAggregation` → `AvgAgg` (rename confirmed)
- [ ] `TotalHits()` → `.Total.Value` (int64 in object)
- [ ] `*hit.Source` → `hit.Source_` (no pointer dereference)
- [ ] `elastic.IsNotFound` → `esclient.IsNotFound`
- [ ] `go build ./...` passes
- [ ] `go vet ./...` passes
- [ ] `go test ./... -race` passes

---

*Source: elastic/go-elasticsearch v9 docs · olivere/elastic wiki · internal migration design*
*Last updated: 2026-06-03*
