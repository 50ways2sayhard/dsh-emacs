# 111 — Asynchronous session drafts

## Background

At baseline `c20cc5d`, `dsh-emacs-new-session` displayed its buffer only after
`session/create` returned. Three live GUI measurements took 451–857 ms from
command to open, including 437–794 ms awaiting creation and 3–16 ms initializing
the chat. Direct HTTP creation took 419–536 ms with sub-millisecond TCP setup.
The main delay was host creation, not buffer rendering. The user chose immediate
drafting while the host works; this changes the UI feedback boundary, without
claiming faster Agent initialization.

## Decision

Display a plain editable draft before readiness checks, resolve readiness and
the project workspace asynchronously, then activate that same buffer on success.
The existing open-session initialization is shared without its server guard or
window selection. A pending draft has no active session identity, so commands
cannot fall back to the previously opened chat.

Each draft captures its creation arguments and one client-generated session ID.
Retry uses that identity for the host's idempotent adoption contract. Each attempt
has a distinct local token; stale callbacks and server changes cannot activate a
newer attempt. Failure keeps the draft and error visible; C-c C-c retries without
sending. Closing the draft suppresses activation and cancels readiness polling.

## Why

Creating a normal chat before host acceptance would expose commands and streams
to an unconfirmed session. A separate draft mode supplies ordinary editing while
keeping those capabilities unavailable. Increasing a liveness cache TTL would
save only a small probe and would not remove the measured host delay. Background
workspace creation replaces the synchronous seam recorded in 006; failure now
stops instead of silently changing the requested workspace placement.

Server readiness remains owned by the server module. Its asynchronous path
combines probing and token exchange, bounds waiting, starts only local hosts and
does not repeatedly relaunch an exited process. Interactive installation/token
entry remain explicit user steps. No worker thread or general job abstraction is
introduced.

## Consequence

README, customization and architecture docs describe draft editing and retry.
Tests cover delayed/reordered responses, separate drafts, stable identity on
retry, activation-hook failure, directory capture, workspace failures, server
changes, closed buffers, readiness timeout, auth and startup failure.
Four real GUI samples returned with the draft selected in 1.3–13.1 ms;
activation took 0.51–0.74 seconds, including a narrowed-draft check. Character insertion before the response,
text/point preservation, follow-stream readiness and unchanged window focus
were verified. All 28 real-server RPC/event-stream checks passed, as did a real
refused-connection startup probe and an HTTP 303 token-exchange regression.
Code is left uncommitted pending explicit user authorization.

## Known limitations

Host creation time is unchanged. Closing a draft after dispatch cannot revoke an
accepted creation; the session may still appear in the list. A pending draft
supports text editing; chat completion and attachments become available after
activation. Local project discovery remains synchronous filesystem work, measured
at 0.5–5 ms here. A creation RPC that never completes retains the pending draft
until the user closes it; this change does not add a new transport timeout policy.
