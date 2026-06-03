# normalize.jq — strip volatile, non-deterministic fields from an ES _search
# response (or request) so that golden diffs reflect real query semantics only.
#
# Usage: jq -S -f normalize.jq response.json
#   -S sorts object keys recursively for stable comparison.
#
# Removes:
#   .took              query latency (always varies)
#   ._shards           shard counts/timing (cluster-dependent)
#   ._scroll_id        opaque cursor
#   .hits.max_score    float scoring jitter; relevance scores are not stable
#   .hits.hits[]._score   per-hit score jitter
#   .hits.hits[]._type    mapping types removed in ES7+ (always absent on 9.x)
# Canonicalizes (so ES6 and ES9 captures are directly comparable):
#   .hits.total   number (ES6) -> {value,relation} (ES7+) form, KEEPING the count
#                 so a real count difference still surfaces.
# Keeps hit identity and source so we still catch "different documents matched".
# Sorts hits by _id so equal-score ordering differences don't create false diffs.

walk(
  if type == "object" then
    del(.took, ._shards, ._scroll_id, ._clusters)
  else . end
)
| if has("hits") and (.hits | type == "object") then
    .hits |= (
      del(.max_score)
      # Canonicalize total to the ES7+ object form, preserving the count.
      | if (.total | type) == "number" then .total = {value: .total, relation: "eq"} else . end
      | if has("hits") and (.hits | type == "array") then
          .hits |= ( map(del(._score, ._type)) | sort_by(._index, ._id) )
        else . end
    )
  else . end
