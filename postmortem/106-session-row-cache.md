# 106 — Reuse session visual rows without retaining command targets

## Background

The row-local reconciler from [078](078-session-list-row-updates.md) preserves
markers and avoids whole-buffer multibyte diffs. The offline probe from
[105](105-render-work-reports.md) showed the remaining construction cost: a
single title update still lays out all 540 rows before replacing one row.
The implementation baseline is `e63650c` (session rendering unchanged from
`e8cf554`), with the separate 105 diagnostic changes in the index. This decision
is recorded in the working tree; no commit has been created for it yet.

## Decision

Cache only visual row strings in the destination session-list buffer. Compare
resolved display inputs, not session object identity. Still construct a full
source, refresh all command metadata, walk descendants and publish all target
properties. Retain the new cache only after publication succeeds; its entries
are exactly the rows emitted by that render.

## Why

Session structs and their title strings can change in place. A copied display
snapshot catches those updates; a mutable session pointer is not a safe cache
key. Relative time must be resolved before comparison, and child mode/activity
must participate even when the parent row itself is unchanged. Named faces
remain symbolic, so theme face changes do not freeze old color values.

Keeping metadata outside the cached string prevents a visually identical
replacement session or catalog entry from leaving commands attached to stale
objects. A hit also cannot skip the subtree: a new grandchild or an error notice
may arrive without changing the parent's own layout. Pruning by the emitted
rows bounds retention and makes collapse/removal handling straightforward.

The alternative property-publication optimization remains rejected (105): fewer
setter calls did not demonstrate faster updates, and comparing only the first
character of a run cannot detect stale properties in its interior. No retained
render tree, recursive subtree cache or fragment invalidation change is needed
for this narrower optimization.

## Consequence

The 540-session single-title fixture still visits 540 rows but performs one
visual layout instead of 540; a fully warm unchanged list performs none.
Source size, character edits and property publication stay the same. The
report now distinguishes `:session-row-builds` from `:session-rows`.

The cache is retained on the strength of an independent compiled comparison:
16 alternating pairs per case (after two discarded warmups) measured median
paired savings of 0.613 ms / 9.496% for warm ASCII titles and 1.281 ms / 16.731%
for warm CJK/mixed titles. Cache was faster in 13/16 and 15/16 pairs respectively.
Cold differences were within noise. All samples, including a slower CJK cache
outlier, were retained. An earlier probe incorrectly supplied an ISO timestamp
to a Unix-time formatter; its timings and apparent cold penalty were superseded
by one corrected trial using a shared numeric millisecond timestamp. The table
and complete measurement method are in the performance document below.

Tests cover display invalidation, mutable titles, replacement command targets,
cold/warm propertized equality, external target edits, child updates/notices,
pruning and buffer ownership. The existing focus and marker tests still run.
The user-facing entry is in [CHANGELOG](../CHANGELOG.md); measurements and the
current behavior are documented in
[streaming performance](../docs/streaming-performance.md#session-visual-row-reuse-106).

## Known limitations

Cold renders allocate a cache and copy display inputs. Every refresh still
resolves all visible rows and rebuilds/publishes the complete temporary source,
so construction counts do not imply the same reduction in latency. Cache
memory scales with visible rows. Nested objects stored as text-property values
must be treated as read-only; snapshots do not deep-copy arbitrary property
values. Repair coverage is for character edits and ordinary property setters.
Batch timings exclude GUI redisplay, network
traffic and user input; no GUI smoothness or end-to-end latency claim follows.
The implementation adds no post-27.1 API, but local runtime validation uses
Emacs 31.1.50 rather than an Emacs 27 binary.
