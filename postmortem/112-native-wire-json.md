# 112 — Native JSON decoding at the transport boundary

## Background

The working tree based on `c20cc5d`, including staged draft work from
[111](111-asynchronous-session-drafts.md), still used the Lisp JSON reader for
HTTP and WebSocket input. First-open latency persisted after the repaint fixes
in [081](081-refresh-drain-batched-repaint.md) and row reuse in
[106](106-session-row-cache.md). On the live 655-session, 17-workspace host,
the approximately 531 KB list value took 64–93 ms to parse in the first probe;
struct conversion took 9–10 ms and cold buffer rendering 19–31 ms.
The measured target is transport decoding, not row rendering.

## Decision

Use native JSON parsing at the HTTP and event-stream boundaries through one
protocol-owned decoder, retaining the Lisp reader when native JSON is absent.
Both readers explicitly preserve symbol-keyed alists, vector arrays, nil nulls
and `:json-false`. UTF-8 decoding and error handling stay with the transports.

## Why

An alternating live trial on Emacs 31.1.50 measured median buffer parsing of
99.49 ms with the Lisp reader and 5.86 ms with the native reader. All six
responses decoded identically with both readers. This removes a measured cost
without adding cache state, delaying frames or changing list publication.
Native parsing exists in Emacs 27; availability is checked because builds can
omit it. The fallback fixes its representation options too, preventing user
json.el settings from changing the wire shapes.

## Consequence

Large first-open responses and stream baselines require less client CPU.
The same decoder serves synchronous RPC, asynchronous HTTP and both socket
dispatch paths. Tests cover strings, buffer positions, Unicode, nested values,
false/null distinctions and malformed input with both readers. Measurements and
scope are recorded in [the performance guide](../docs/streaming-performance.md#native-wire-json-decoding-112).
This record describes uncommitted work; no new commit is implied.

## Known limitations

Server response time remains significant. The alternating requests had varying
arrival times, so their total-duration difference is not an isolated parser
speedup or a GUI first-paint guarantee. Rendering measurements exclude redisplay.
Builds without native JSON retain their previous parser cost. Local runtime
validation uses Emacs 31.1.50, with the fallback forced in tests; no Emacs 27
binary was used. JSON embedded in tool arguments remains outside this change.
