#!/usr/bin/env bash
# replay.sh — POST a saved query body to Elasticsearch _search and store the
# normalized response + metadata. Works against ES 6.x and 9.x (body search API).
#
# Usage:
#   ES_URL=https://localhost:9200 [ES_AUTH=user:pass] \
#     replay.sh <index> <req.json> <out.res.json> <out.meta.json>
#
# Env:
#   ES_URL   (required) base URL, e.g. https://localhost:9200
#   ES_AUTH  (optional) "user:pass" for basic auth
#   ES_CA    (optional) path to CA cert for TLS
#
# Notes:
#   - Secrets come from env, never hardcode them here.
#   - Response is normalized via normalize.jq so golden diffs are meaningful.
#   - Exits non-zero on HTTP error or missing deps so callers can gate on it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

err() { printf 'replay.sh: %s\n' "$*" >&2; exit 1; }
command -v curl >/dev/null || err "curl not found"
command -v jq   >/dev/null || err "jq not found"

[ "$#" -eq 4 ] || err "usage: replay.sh <index> <req.json> <out.res.json> <out.meta.json>"
INDEX="$1"; REQ="$2"; OUT_RES="$3"; OUT_META="$4"
: "${ES_URL:?set ES_URL}"
[ -f "$REQ" ] || err "request body not found: $REQ"

AUTH=(); [ -n "${ES_AUTH:-}" ] && AUTH=(-u "$ES_AUTH")
CA=();   [ -n "${ES_CA:-}" ]   && CA=(--cacert "$ES_CA")

URL="${ES_URL%/}/${INDEX}/_search"

# Capture body + HTTP status separately.
HTTP_BODY="$(mktemp)"; trap 'rm -f "$HTTP_BODY"' EXIT
STATUS="$(curl -sS "${AUTH[@]}" "${CA[@]}" \
  -H 'Content-Type: application/json' \
  -X POST "$URL" \
  --data-binary "@$REQ" \
  -o "$HTTP_BODY" -w '%{http_code}')"

ES_VERSION="$(curl -sS "${AUTH[@]}" "${CA[@]}" "${ES_URL%/}" | jq -r '.version.number // "unknown"' 2>/dev/null || echo unknown)"

jq -n --arg index "$INDEX" --arg path "/${INDEX}/_search" \
      --arg status "$STATUS" --arg ver "$ES_VERSION" \
      '{index:$index, method:"POST", path:$path, http_status:($status|tonumber), es_version:$ver}' \
      > "$OUT_META"

if [ "$STATUS" -lt 200 ] || [ "$STATUS" -ge 300 ]; then
  cp "$HTTP_BODY" "${OUT_RES}.error"
  err "ES returned HTTP $STATUS for $REQ (raw body saved to ${OUT_RES}.error)"
fi

jq -S -f "$SCRIPT_DIR/normalize.jq" "$HTTP_BODY" > "$OUT_RES"
printf 'replay.sh: %s -> %s (ES %s, HTTP %s)\n' "$REQ" "$OUT_RES" "$ES_VERSION" "$STATUS"
