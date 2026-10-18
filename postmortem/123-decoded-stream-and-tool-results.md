# 123 — Decode stream envelopes and share tool-result application

Superseded in part by [124](124-shared-interaction-owner.md) for prompt-slot
ownership and [125](125-follow-snapshot-protocol-boundary.md) for follow item
and snapshot decoding; nested projection payloads remain raw.

## Background

At `3c4f069`, chat streams read mux envelope fields in the event dispatcher,
while the core stream converted the same envelope into a private plist.
Both paths depended on a renderer field reader. Late question settlement
also constructed a nested wire-shaped tool event just to reach the existing
card updater. The boundary problem was in events and rendering, not in
WebSocket framing or the timed-question workflow from [073](073-timed-question-answers.md).

## Decision

Use protocol structs at these two existing boundaries. Incoming mux envelopes
become `dsh-protocol-mux-frame`; events retains routing, stream retirement and
callback ownership. Tool-result events decode into `dsh-protocol-tool-result`,
and late answers construct that type directly. Both reach one renderer that
updates an existing card; only the event entry point returns a replay sequence.

This records the second refactoring batch based on `3c4f069`,
following [122](122-remove-inactive-transcript-options.md). It removes the
synthetic event limitation recorded there. No public workflow changes.

## Why

The struct replaces two envelope interpretations with one decoder and removes
wire field knowledge from routing. It does not turn unrelated stream payloads
into a generic event model. JSON decoding and error handling stay at the
existing transport boundaries, so invalid input and callback failures retain
their current handling.

The shared tool-result function has two real callers with different sources.
Its purpose is to separate event identity from card state, not to wrap a
single call site. Keeping the existing tool-result struct avoids a second
presentation model and the conversion rules that would come with it. Tool
variants continue to use their existing body renderers.

## Consequence

The event renderer returns the original sequence for ordinary results,
missing calls and plan cards; hidden tool results remain no-ops. Late answers
respect visibility, update only pending question cards and preserve call
identity and folding. Settled projections are still consulted when a delayed
live result or older history page creates the card.

Protocol and event tests cover envelope decoding and routing. Tool and
question tests protect sequence returns, visibility and repeated settlement;
the existing card, plan and history tests retain their behavioral contracts.
Architecture documentation describes the boundary.

## Known limitations

Nested follow snapshots, control/projection items and several tool payloads
still contain raw wire data. They require separate, payload-specific changes;
the mux struct deliberately carries its logical value without decoding it.
Question and approval prompt-slot ownership remains unchanged. Default E2E
smoke covers live stream routing, not the timed-question GUI workflow.
