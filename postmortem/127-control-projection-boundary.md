# 127 — Decode control projections before applying them

Partially superseded by [128](128-follow-projection-view.md): follow projection
blocks now have their own decoded view at the existing late application point.

## Background

At `3c4f069`, events mixed control envelope parsing, projection decoding and
state application. Goal and inbox already had protocol decoders, but events
and Composer still dispatched raw payloads through forwarding functions.
[126](126-context-and-permission-decoders.md) moved context and permission
fields into protocol; [019](019-composer-feedback-and-protocol-boundary.md)
established protocol ownership of goal parsing. This records the sixth
refactoring batch based on `3c4f069`.

## Decision

Decode control increments into a session/key/value projection and baseline
records into per-session values with a complete subagent batch plus ordered
projections. Events owns application order, connection identity and repainting;
Composer accepts a goal struct or nil directly. Remove the two Composer
forwarders and the separate Plan/question update wrappers.

## Why

Increment and baseline consumers need the same payload types. A shared
decoder makes protocol changes local without a parallel dispatch framework.
Baseline grouping also makes two existing contracts explicit: all four
subagent cells must land together, and absent Plan/question capabilities still
carry sequence cuts. Goal/inbox absence differs from an explicit nil cell.

Do not eagerly decode the entire host baseline: a later migration-required
record must leave earlier applied sessions intact. The outer decoder returns
raw nonempty records in order; each session is decoded immediately before
application. This needs no callback, thunk or exception-capture layer.

## Consequence

Valid payloads preserve subagent → Plan/questions → remaining wire order,
one final list repaint and queue process identity. Unknown projection values
remain opaque and ignored by current consumers. Raw fixtures enter through
the existing `dsh-protocol--struct` gate. Commands, defaults and readers do
not change. Protocol/workspace tests cover typed payloads, absence versus
clear, four-cell batches and cross-session partial success; existing routing,
Plan, question, queue and Composer tests cover application behavior.

## Known limitations

A session now decodes fully before it applies. A malformed goal/inbox may
therefore fail before that session's earlier cells take effect; malformed
updates without a live target chat also decode before being dropped. These
errors still surface at the transport boundary. Preserving arbitrary invalid
payload failure timing would require interleaving parsing with side effects.

Nested subagent decoders retain their existing symbol-keyed wire contract;
the JSON reader already supplies that shape. Follow projection blocks,
workspace/`$events` routing and durable event payloads still contain wire
knowledge in their consumers and remain separate work. Emacs 27.1 remains
the supported baseline, without a new compatibility layer.
