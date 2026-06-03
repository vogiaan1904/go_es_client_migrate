#!/usr/bin/env bash
# compare.sh — structural diff of two JSON files (golden vs new) after
# normalizing volatile fields. Used for both request bodies and ES responses.
#
# Usage: compare.sh <golden.json> <new.json>
#   exit 0  -> equivalent (no meaningful diff)
#   exit 1  -> MISMATCH (prints the diff; classify as benign vs wrong per the
#              es-golden-master skill before changing code)
#   exit 2  -> usage / dependency / file error
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

err() { printf 'compare.sh: %s\n' "$*" >&2; exit 2; }
command -v jq >/dev/null || err "jq not found"
[ "$#" -eq 2 ] || err "usage: compare.sh <golden.json> <new.json>"
GOLDEN="$1"; NEW="$2"
[ -f "$GOLDEN" ] || err "golden not found: $GOLDEN"
[ -f "$NEW" ]    || err "new not found: $NEW"

norm() { jq -S -f "$SCRIPT_DIR/normalize.jq" "$1"; }

A="$(mktemp)"; B="$(mktemp)"; trap 'rm -f "$A" "$B"' EXIT
norm "$GOLDEN" > "$A"
norm "$NEW"    > "$B"

if diff -q "$A" "$B" >/dev/null; then
  printf 'compare.sh: MATCH  %s == %s\n' "$GOLDEN" "$NEW"
  exit 0
fi

printf 'compare.sh: MISMATCH  %s != %s\n' "$GOLDEN" "$NEW" >&2
# Prefer a readable structural diff; fall back to line diff.
if command -v delta >/dev/null; then
  diff -u "$A" "$B" | delta || true
else
  diff -u "$A" "$B" || true
fi
echo >&2
echo "compare.sh: classify the diff per es-golden-master skill:" >&2
echo "  - only fields in references/known-benign-diffs.md  -> benign, accept" >&2
echo "  - field/clause/value/range/agg semantics differ     -> WRONG, invoke es-query-equivalence and fix" >&2
exit 1
