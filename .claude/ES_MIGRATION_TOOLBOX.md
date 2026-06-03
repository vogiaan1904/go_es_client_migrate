# ES 6.x → 9.x Migration Toolbox (olivere → go-elasticsearch v9)

A source-agnostic toolbox: it encodes the *method*, and treats **`go build ./...`
+ the live ES round-trip as the authority** — not any hardcoded API signature.
It works on a codebase it has never seen, because the agent discovers exact
signatures by compiling, the same way a person would.

## The two phases

```
PHASE 1  (temp branch)            PHASE 2  (golden-master verification)
─────────────────────             ──────────────────────────────────────
Make it COMPILE on ES 9.          Prove it BEHAVES the same at runtime.

esclient wrapper + all callers    2.1 CAPTURE  (main, OLD code, ES 6.x)
move off olivere onto esclient        record golden request+response JSON
wrappers (esdsl hidden inside).   2.2 VERIFY   (merged + ES 9)
Gate: go build ./... green,           regenerate, compare to golden,
no olivere/esdsl in handlers.         fix wrong mismatches until green.
```

## Artifacts

### Skills (`.claude/skills/`)
| Skill | Phase | Purpose |
|---|---|---|
| `esclient-wrapper-migrate` | 1 | How to migrate wrapper + callers; architecture rules; the compiler is the authority. Has the full olivere↔esdsl reference doc. |
| `es-golden-master` | 2 | Golden capture/compare procedure + `replay.sh`/`compare.sh`/`normalize.jq` scripts + known-benign-diffs reference. |
| `es-query-equivalence` | 2.2 | Diagnosis lens: given a "wrong" query-JSON mismatch, which construct changed and how to fix it. |

### Subagents (`.claude/agents/`)
| Agent | Used by | Scope |
|---|---|---|
| `es-migrator` | `/es-migrate` | Migrate ONE file off olivere; stops only on green build. |
| `es-golden-runner` | `/es-golden-capture`, `/es-golden-verify` | Capture or verify golden for ONE file. |

### Commands (`.claude/commands/`)
| Command | Phase | Does |
|---|---|---|
| `/es-migrate [audit\|<file>\|all]` | 1 | Audit repo, or migrate per-file via `es-migrator`, build-gated. |
| `/es-golden-capture <files>` | 2.1 | Capture golden baselines from OLD code/ES 6.x. |
| `/es-golden-verify <files>` | 2.2 | Compare migrated code/ES 9 to golden; drive fixes. |

## Suggested run order

1. `git switch -c es9-migration` (temp branch).
2. `/es-migrate audit` → review the plan.
3. **(Recommended, before merging)** on `main` with ES 6.x running:
   `/es-golden-capture <high-value files>` → commit `testdata/es-golden/**`.
   Capturing on the OLD branch is what makes Phase 2.2 meaningful.
4. On the temp branch: `/es-migrate all` (or per file) until `go build ./...` and
   `go vet ./...` are green and no handler imports olivere/esdsl.
5. Merge Phase 1; upgrade ES to 9; restore the same data/index.
6. `/es-golden-verify <same files>` → fix wrong mismatches until green.

## Two ideas this toolbox is built on

1. **The compiler is the authority.** The reference doc's code is illustrative
   and was found to contain non-compiling snippets (esdsl builders return
   *unexported* types; several signatures were wrong). Every skill/agent enforces
   the architecture + `go build`, never literal reproduction of the doc.
2. **Behavior preservation is proven, not assumed.** Phase 1 green ≠ identical
   queries. The golden-master round-trip against real ES is what proves the
   migration didn't silently change a query.

## Requirements

- Go toolchain; `go.mod` requiring `github.com/elastic/go-elasticsearch/v9`.
- For Phase 2: `curl` + `jq`; reachable ES 6.x (capture) and ES 9 (verify) with
  the same data; `ES_URL` (and `ES_AUTH`/`ES_CA` if needed) in env — never
  hardcoded.
