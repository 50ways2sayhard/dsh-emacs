# 125 — Decode follow snapshots at the protocol boundary

Superseded in part by [126](126-context-and-permission-decoders.md) for context
and permission payload decoding; projection envelopes and core baselines remain raw.

Further superseded by [127](127-control-projection-boundary.md) for control
projections and [128](128-follow-projection-view.md) for the late follow
projection view. The snapshot itself still retains the raw block until then.

## Background

At `3c4f069`, the events module read `session/follow` item types and snapshot
fields through the renderer's wire-field helper. It filtered history records
locally, then called separate protocol helpers for execution and assistant
baselines. This scattered the snapshot contract across events and protocol.
[123](123-decoded-stream-and-tool-results.md) moved the mux envelope boundary
but deliberately left its logical payload raw.

## Decision

Decode logical follow items and opening snapshots into protocol structs.
The snapshot owns field normalization, record selection and the existing
execution, Plan and assistant views. Events owns when those views are applied.
Remove the two one-use snapshot decoder wrappers. Durable event records and
the remaining projections block retain their existing consumers and identity.

This records the fourth refactoring batch based on `3c4f069`,
following [124](124-shared-interaction-owner.md). No public workflow changes.

## Why

A snapshot is not a backward history page: it accepts cursor -1 and does not
impose the page decoder's strictly increasing, nonnegative sequence contract.
Reusing that decoder would change behavior. Execution also needs the whole
retained window, including records below the transcript anchor. Keeping these
rules in the snapshot constructor gives the boundary a concrete contract.

Decoding and application have different responsibilities. Execution and Plan
must be seeded before history rendering can yield to newer live events.
Question settlements must be applied after history creates the tool cards.
Moving decoding does not justify changing either ordering rule. A projections
wrapper that only renamed raw fields would add indirection without removing
the existing consumers' wire knowledge, so it is deferred.

## Consequence

The event dispatcher reads a decoded type and payload. Snapshots carry one
normalized record list and the baselines needed by their consumers; live
assistant frames use the existing decoded frame type. Raw fixtures and decoded
values enter through `dsh-protocol--struct`, without a second compat layer.

Protocol tests cover key and array forms, record identity/order, empty
baselines and absent capability watermarks. Event tests exercise the raw and
decoded paths with actual history rendering and projection application.
Existing execution and Plan tests protect newer updates received while
history renders. Architecture documentation describes the scope.

## Known limitations

Core control baselines, projection increments and nested projection payloads
still contain raw fields. Their absence/null/false and tombstone semantics
differ by consumer and require a separate change. Durable event payloads and
packed assistant chunks also remain raw where their existing renderers expect
them; this change does not create a universal event model.
