# 134 — Complete the event consumers’ protocol boundaries

## Background

After `364cecb` and the title/deliverables boundary in [133](133-title-and-deliverables-boundaries.md),
renderer, mode-line and input history still interpreted wire objects themselves.
This record describes the uncommitted continuation based on `845325e`.
The card contracts in [045](045-read-and-diff-tool-cards.md),
[057](057-aligned-diff-context.md) and [100](100-goal-tool-cards.md) remain unchanged.

## Decision

Decode event metadata, message blocks and sources, chunks, attempt streams,
request configuration, usage and tool-specific payloads in protocol. Delete the
renderer and token modules’ generic field readers. Keep rendering, history
ordering/deduplication, usage accumulation and refresh decisions with consumers.

Use semantic views where several facts travel together, and scalar or ordered
row decoders where a struct would add no information. Tool argument views keep
the original object solely for generic JSON display. No consumer interprets
its fields. Existing raw tool payload fixtures have an explicit constructor
mode; production calls select the event envelope.

## Why

Moving a generic field reader would leave wire interpretation distributed.
An eager universal event decoder would instead validate unrelated payloads at
routing time. Consumer-specific decoding makes ownership explicit while keeping
validation at the existing use points. In particular, assistant render entry
points accept typeless payloads, so their message envelope must be selected
explicitly rather than inferred from an event type.

Read/diff validators retain their all-or-nothing rules, question results retain
pending/empty distinctions, and cleared goal results remain distinguishable
from unrelated JSON. Formatting and card fallback policy stay in renderer.

## Consequence

No commands, options or intended display behavior change. Existing integration
tests exercise streaming, attachments, history, cards and mode-line. Added
protocol tests distinguish message envelopes, attachment precedence, request
configuration, usage aliases and exact tool-name summary priority. The full
verification gate and real-server E2E cover the combined migration.

## Known limitations

Routing still passes raw durable events to semantic decoders; this is intentional,
not a claim that every event is eagerly converted once. Separate consumers may
decode the same message. Outbound RPC serialization is outside this change.
Emacs 27.1 remains the declared baseline; validation used Emacs 31.1.50.
