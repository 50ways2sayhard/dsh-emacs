# 105 — Measure render work before changing publication

## Background

[ETAF's incremental update and publication design](https://etaf.top/zh-cn/incremental-updates-and-publication/)
separates retained-tree recomputation from buffer edits and reports both. The
same distinction matters here, but dsh-emacs already has complete fragment
snapshots, a conservative cache and row-local session reconciliation. The
fragment cache decision is recorded in [026](026-fragment-performance-cache.md)
(history: `2bb3f85`); session row handling in
[078](078-session-list-row-updates.md) (history: `5bfbfd4`, `a88464a`). Small
visible edits alone cannot show whether those paths do excessive work.

## Decision

Add an explicitly invoked offline diagnostic script and retain the existing
production renderer. There is no new runtime observer, cache protocol or
retained-tree abstraction. This record describes the working-tree change based
on `e8cf554`; no new commit is implied.

## Why

The representative probes distinguish computation, character edits and
property setter requests. An unchanged warm fragment needs no reconstruction;
a nearby stream append triggers one reconstruction but no fragment writes.
A 5,000-line card title update reconstructs 50,009 characters while replacing
one character and publishing the full-block state property. A 540-session
single-title update constructs all rows but confines character changes to one
54-character row. Its 3,246 property calls cover 29,241 requested characters.

A local experiment skipped session property intervals only when all values
were identical objects. It inspected both source and target boundaries so
interior stale metadata could not be overlooked, and preserved fresh mutable
session objects even when their contents were equal. Requests fell to 545
covering 591 characters, but a five-sample uninstrumented trial was 17.251 ms
versus a preceding baseline's 10.595 ms. This was not a controlled GUI study;
subsequent baseline timings varied too. No demonstrated time benefit justified
the additional traversal and comparison code, so the experiment was removed.

ETAF-style dirty paths or local cache generations would add ownership and
invalidation rules to solve a cost not yet shown to dominate. The existing
external-edit recovery and full-snapshot contract are worth preserving.
Always-on tracing would itself add overhead; the developer script instead
scopes advice/hooks to one synchronous operation and cleans them up on error.

## Consequence

[The performance guide](../docs/streaming-performance.md#render-work-reports-105)
provides the command, fixture definitions, measurements and field semantics.
The report keeps ordered character-change notifications and requested property
intervals separate; it does not claim that either measures pixel damage.
Independent timing samples exclude instrumentation. Unit tests check buffer
scoping, cleanup, unchanged-cache behavior and propertized output equivalence;
the script joins the syntax gate. No normal chat behavior changes.

## Known limitations

All visible session rows are still rebuilt and their properties republished.
Unrelated buffer writes still invalidate fragment caches. Full-block fragment
state publication remains intentional. Reports require interpreted dsh-emacs
sources and do not observe suppressed hooks, deferred timer callbacks or GUI
redisplay. Synthetic macOS/Emacs 31.1.50 timings are not an Emacs 27 runtime
validation, a real-server benchmark or a responsiveness guarantee.
