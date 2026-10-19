# 140 - Outbound request encoders and stable wire JSON

## Background

At `47c5162`, HTTP transport had moved to the server module, but the outbound
limitation in [135](135-rpc-response-boundaries.md) remained. Both model pickers
built session/selectModel independently, and sessionId-bearing request bodies
were spread across business modules. RPC and mux serialization inherited user
json.el settings, unlike the fixed inbound reader.

## Decision

Continue the existing protocol `*-request` convention, returning plain argument
alists. This batch moves session RPC arguments, workspace mutations, job
list/follow/kill and skills/list, plus prompt text content and session/follow.
Move client-request and mux open/cancel JSON envelopes into protocol too; delete
the old builders instead of retaining forwarding wrappers.

Use one wire JSON writer with explicit null/false sentinels and compact
formatting, separator and field order settings. Keep the Lisp encoder for now.
This records the uncommitted continuation based on `47c5162`; no commit is
created automatically.

## Why

Method-specific encoders give field names and optional-field omission a single
owner, symmetric with decoders, without request structs or a dispatch registry.
Endpoint selection, ids, time zones, path expansion, callbacks and UI policy
remain with their current owners. HTTP still owns authentication and UTF-8;
events still owns mux lifecycle and WebSocket framing.

Native json-serialize is not a drop-in replacement: existing question answers
contain list arrays, including nested selected labels. It rejects those lists.
A fixed Lisp writer removes customization-dependent wire failures without
changing opaque payload shapes or introducing heuristic normalization.

## Consequence

Both model-selection paths share one encoder. No inline sessionId request
construction remains outside protocol. Empty argument objects, optional-field
omission, prompt content order and session-scoped job follows keep their existing
contracts. JSON customization no longer changes RPC/mux wire semantics; a
regression test fails on the previous writer before passing with the fixed one.
Protocol contracts and existing caller tests cover the migrated batch.
The complete verify gate, including Motion Line integration, passes locally on
Emacs 31.1.50. The existing-server RPC/mux E2E passes 28 checks and archives its
test sessions; optional delegation and running-status suites are not enabled.

## Known limitations

Commands, references, goals, providers and interaction argument encoders remain
distributed. Nested queue actions and attachment parts are still supplied as
wire-shaped subdocuments. This is a bounded migration, not completion of all
outbound ownership. Native serialization can be reconsidered after the remaining
list-array producers have explicit vector contracts. Local tool-argument
display and settled-answer replay are not RPC/mux transport serialization.
