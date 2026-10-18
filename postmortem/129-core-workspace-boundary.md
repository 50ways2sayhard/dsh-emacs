# 129 — Decode core workspace items before cache application

Superseded in part by [130](130-host-event-decoding-boundaries.md): `$events`
envelopes now decode in protocol; the workspace and replay decisions remain.

## Background

At `3c4f069`, the protocol module already defines a workspace-list decoder,
but the core event consumer separately reads baseline and incremental wire
fields through the renderer. [127](127-control-projection-boundary.md) and
[128](128-follow-projection-view.md) isolated projection payloads; the core
workspace path still mixes decoding with cache application. This records the
eighth refactoring batch based on that commit.

## Decision

Decode core items into a type and payload in protocol. Reuse workspace-list
for baselines, workspace for upserts, and plain ids/lists for the remaining
workspace updates. Events owns application, repainting and replay recording.
Control baselines retain raw session records until sequential application;
projection increments reuse their existing decoder.

## Why

This removes duplicate baseline decoding and makes workspace field changes a
protocol concern. Scalars and lists suffice for incremental payloads; a new
struct per frame type or a generic dispatch registry adds no current value.
The outer item is the only new shared shape, and raw fixtures enter through
the existing `dsh-protocol--struct` gate.

The core connection carries several streams with different baseline shapes.
Preserving the existing non-nil `items` test matters: an empty vector clears
the workspace cache, while absent/null items selects control. Decoding an
entire control baseline eagerly would let a later migration-required session
prevent earlier sessions from applying, so the outer decoder leaves it raw.

## Consequence

No command, default or UI behavior changes. Baseline cache replacement and
incremental cache mutation still precede repaint/replay recording as before.
Refresh replay keeps chronological order, including an explicit empty archive
set. This preserves the cache-first list model in
[059](059-session-list-does-not-refetch-on-open.md) and the refresh ownership in
[081](081-refresh-drain-batched-repaint.md).

Tests cover both raw and decoded items, replacement of an existing workspace,
membership, ordering, removal, archive clearing and a late refresh snapshot.
Separate protocol assertions protect baseline routing, array normalization,
decoded projection payloads and raw control/event identity.

## Known limitations

`$events` payloads and durable event bodies still contain wire fields in their
consumers. They are separate migrations; ready/emit/waterfall/cancel bodies
remain unchanged here. Nested workspace rows retain their existing symbol-key
contract, matching the JSON reader. No new validation or malformed-frame
recovery policy is introduced. The Emacs 27.1 baseline is unchanged.
