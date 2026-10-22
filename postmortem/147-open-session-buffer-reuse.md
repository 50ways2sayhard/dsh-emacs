# 147 — Reopening a session reuses its live chat buffer

## Background

`dsh-emacs-open-session` initialized a session on every call, including
when that session's chat buffer was already live: it ran
`dsh-emacs--activate-chat-buffer`, which re-ran the buffer sync, the mode-line
model/context feeds, the catalog prefetches and `dsh-emacs-events-connect`.
The anchor gate kept the reconnect from repainting the transcript, but the
connect still tore down and rebuilt the session's mux socket and returned
point to the input marker.  So "go back to that chat" from the session list,
`M-x dsh-emacs-switch-session` or an `@` reference silently moved the cursor
out of a half-read transcript and paid for a fresh WebSocket handshake.  The
session-list path (`dsh-emacs-open-session-at-point`) also ran
`dsh-emacs-server-ensure` first, although selecting an existing buffer makes
no RPC.  This is the chat-buffer counterpart of the live-list reuse in
[059](059-session-list-does-not-refetch-on-open.md): there the list already
retained its state, here the chat buffer did.

## Decision

`dsh-emacs-open-session` only selects a live buffer: it sets
`dsh-emacs--current-session`/`dsh-emacs--current-buffer` and pops to the
buffer.  Buffer creation, `dsh-emacs-server-ensure`, activation, prefetch and
the mux connect remain on the create path only.  A killed buffer has already
left `dsh-emacs--chat-buffers` through `dsh-emacs--chat-buffer-untrack`, so
it still takes that path.

## Why

Everything activation produces already belongs to the live buffer:
`dsh-emacs--chat-buffer-sync` is re-run by `dsh-emacs--chat-buffers-sync-all`
on every cache refresh and by live `session/title` events; the model,
context and preset feeds are re-pushed by their projection frames and by
`sync-all`; the command/skill/reference prefetch caches are buffer-local and
persist; and the mode, local keymap and mode-line hooks are installed once.
Re-running those to "be safe" only did redundant work and moved point.

The alternative — keep reconnecting on reopen so it doubles as a resync —
was rejected because recovery already has an owner: the sentinel and
`dsh-emacs-events--schedule-reconnect` recover a dropped socket, a
synchronous connect failure re-arms that timer, and `C-c C-r`
(`dsh-emacs-refresh`) is the explicit "tear down and follow again" command.
Overloading navigation with recovery made the common action destroy local
state to serve a rare one.  Keeping activation minus the connect was also
rejected: its remaining steps are already maintained by the cache/event
paths listed above, so it would be a no-op pass that still risked clobbering
buffer state.

## Consequence

- Reopening a live session preserves its transcript, draft, point, folds and
  mux stream; selecting it costs no HTTP probe and no handshake.
- `ADDRESS` (the subagent address) now applies only to initialization: a
  live buffer was addressed when it was created.  Subagent children are
  filtered from the session list, and the picker path always initializes
  them with their address, so the ordinary paths keep their address.
- `dsh-emacs-open-session-at-point` no longer ensures the server before
  selecting a live buffer; the create path still does.
- Tests: `dsh-emacs-test-session-open-live-buffer-preserves-state`,
  `dsh-emacs-test-lifecycle-open-session-replaces-killed-buffer`, and the
  reopen assertions in
  `dsh-emacs-test-lifecycle-open-second-session-connects-its-own-stream`
  (which now expects no connect and no disconnect on reopen).
- Docs: `docs/architecture.md` (snapshot-first), `docs/modeline.md` (clock
  and history replay), `docs/slash-commands.md` and `docs/customization.md`
  (prefetch runs on the first open) distinguish first open from switching
  back.

## Known limitations

- A live buffer whose stream was deliberately torn down (for example a
  major-mode switch runs `change-major-mode-hook` →
  `dsh-emacs-events-disconnect`) is no longer healed by reopening it.  `C-c
  C-r` reconnects, or kill the buffer and open the session again.
- Reopening is no longer a way to force a fresh `session/follow` snapshot;
  `C-c C-r` is.
