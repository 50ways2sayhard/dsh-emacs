# 139 — Required package calls and server-owned HTTP transport

## Background

At `454c9af`, after the unused-helper cleanup in `aad320e`, 28 package-owned
calls still used `fboundp` guards. Missing required definitions silently
skipped rendering, projection updates or cleanup. HTTP/RPC functions lived
in the entry point that already loaded their consumers, so feature modules
declared reverse dependencies on the application assembler. Authentication
lived separately in the server module.

## Decision

Call required package functions directly, with accurate declarations across
intentional cyclic boundaries. Retain optional external, version/build and
dynamic-dispatch checks, and all state/liveness guards.

Move HTTP/RPC implementation, retaining its existing internal call seams, to
`dsh-emacs-server.el`. Consumers require the owner directly. Keep session
arguments with the session coordinator and response-envelope interpretation
in protocol. Share UTF-8 normalization plus JSON body reading between the
synchronous and asynchronous paths. The server supplies Cookie headers for
HTTP and explicit Basic plus Cookie for raw WebSocket requests.

## Why

This removes silent dependency failures and reverse RPC declarations without
adding a new module, forwarding API or generic transport framework. The server
already owns base URLs, browser-session authentication and 401 invalidation;
requiring it needs no UI or entry-point dependency. HTTP and WebSocket share
an authentication owner, not an identical header policy: the URL library
already handles Basic credentials in URL userinfo.

Do not merge sync/async error handling merely to reduce repeated lines. Sync
checks HTTP status and returns an error pair; async follows URL callback status
and dispatches only to a live originating buffer. Callback errors propagate,
`quit` is consumed, and the response buffer is gone before dispatch. Binary
upload bodies remain byte-exact, with their explicit direct envelope decoder.

## Consequence

No intended changes to commands, options, keybindings or normal authentication.
The transport can load without the chat entry point. Tests characterize
response values, UTF-8, raw uploads, callback ownership/cleanup and errors,
HTTP versus WebSocket headers, and isolated server loading. Architecture and
AGENTS ownership rules now match the implementation. This record describes
the uncommitted change based on `454c9af`; no commit is created automatically.
The transport-location portion of [008](008-browser-session-auth.md) is
superseded, not its authentication model; [135](135-rpc-response-boundaries.md)
still governs decoding.

## Known limitations

Header stripping remains at each HTTP boundary: async missing-header failures
still occur outside its JSON catcher, unlike malformed JSON. Consolidating
that exception boundary would be a separate bug fix. The existing zero-argument
401 invalidation is not request-generation-aware, so a delayed failure can
clear newer cached auth; this refactor does not add a new connection model.
Readiness probes and token exchanges retain their pre-authentication policy.
Outbound endpoint payloads remain distributed, and cyclic UI calls still
need the entry point to assemble the package. Source reload does not remove
old definitions or migrate retained callbacks; restart for a clean definition
set, per [115](115-source-hot-reload.md).
