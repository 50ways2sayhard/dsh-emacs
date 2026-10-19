# 135 — Finish inbound RPC and embedded document boundaries

Outbound-construction limitation partially superseded by
[140](140-outbound-request-encoders.md).

## Background

The event migration in [134](134-event-consumer-boundaries.md) left inbound
RPC envelopes and a few endpoint results in business modules. Plan JSON and
host-encoded session reference URIs still parsed outside protocol. This records
the uncommitted continuation against `845325e`.

## Decision

Use one protocol result decoder for ordinary RPC envelopes and bare upload
results, with an explicit envelope choice. Delete the core unwrap helper and
call the decoder directly. Reuse the existing session-list decoder and decode
workspace order, job-kill outcomes and error messages in protocol.

Move Plan argument parsing and session URI decoding into protocol. Preserve
Plan JSON error reporting at the rendering boundary and preserve match data
while decoding references, so mention scanning still makes forward progress.

## Why

The transport should deliver results and invoke callbacks; response field
names and provider error precedence belong to protocol. Upload has a different
outer envelope but the same success discriminator. Explicit selection avoids
heuristics that mistake a provider failure for a successful upload. Local
staged attachments, caches and rendering state are not wire responses and keep
their existing lightweight representations.

## Consequence

No intended user-visible changes. Error precedence, upload callback exception
propagation, workspace order, Plan fallback and URI scan progress remain
covered by existing tests. Additional protocol tests distinguish nested RPC
and direct upload envelopes and verify Plan parsing under JSON customization.
The complete gate and real-server E2E validate the combined change.

## Known limitations

Outbound request construction remains distributed among endpoint owners; this
change completes inbound interpretation, not a redesign of serialization.
Validation runs on Emacs 31.1.50; the declared minimum remains Emacs 27.1.
