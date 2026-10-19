# 141 - Consume live model-selection projections

## Background

After `2c7402f`, a live Emacs chat still displayed opencode's DeepSeek model
while both session/projections and a fresh session/list returned
magpie-slim-responses' codex/gpt-6.1-sol as lastUsed and next. Emacs' cached row
also retained DeepSeek. The same missing modelSelection dispatch exists in the
parent `47c5162`; outbound request encoding did not switch the actual model.
The previous gate/E2E did not assert externally changed model display.

## Decision

Decode modelSelection.lastUsed to the existing selection struct for session
rows, core updates/baselines and follow snapshots. Apply it to the existing
cached row and matching live chat independently, including chats whose list row
has not arrived. Keep the legacy nested fixture gate at consumer boundaries.

Record/replay model updates during list refreshes. Begin the refresh span at
the actual internal fetch, not its public wrapper: model selection also invokes
that internal fetch directly. During follow history rendering, capture live
core model updates in dynamically scoped per-session slots. Prefer the captured
live value when applying the late snapshot projections.
The global cache fetch uses its own hidden callback buffer, so closing the
originating chat cannot suppress its completion and strand refresh depth.

## Why

The missing layer is protocol/event consumption, not encoder output or modeline
formatting. Request/header and context feeds do not replace a live projection
subscription, and an unchanged session row can overwrite their correct value.
Neither polling nor another RPC on every message fixes that ownership gap.

lastUsed describes the model that actually ran; next can describe only a pending
choice. Preserve that distinction. A missing lastUsed does not clear a known
model, while a valid model with no reasoning effort clears stale effort. Scoped
snapshot slots address updates arriving during history yields without assuming
cached-record and connected-session watermarks share a sequence domain.

## Consequence

The observed modeline was restored by a normal list refresh without changing
the server selection. Reproductions first fail on ignored live updates, stale
internal list callbacks and model updates delivered during snapshot history;
the fixed consumers pass them. No commit is created automatically for this fix.
A separate fresh Emacs probe connects to the affected session's real follow
stream with no cached row and request-model event feeds disabled. Its snapshot
alone restores codex/gpt-6.1-sol from the server projection.

## Known limitations

The slots protect the active snapshot span, not a global total order across all
independently arriving cached baselines. No sequence/generation model is added.
This changes a short-lived follow projection struct layout; restart Emacs for
a clean definition set, as described in the source-reload contract. The manual
list refresh corrects the running display but does not hot-install this fix.
