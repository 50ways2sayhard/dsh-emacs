# 148 — Open sessions with complete rounds

## Background

The complete-round loader from [110](110-load-complete-rounds.md) made
`C-c C-o` reliable, but opening still requested only a message-count tail.
A long round could therefore open without its question or early tool work.
This was an Events/history coordination gap, not a rendering defect. The
follow path retained by `1beaaf1` seeds history before consuming gapless live
frames; changing that transport order would introduce a different problem.

## Decision

Use `dsh-emacs-history-rounds` for both opening and manual pagination. Follow
requests a round-aligned tail with the existing message budget. Its decoded
snapshot counts valid turn starts. If a fresh transcript contains fewer
starts and older history remains, the shared history controller fetches the
missing rounds using the snapshot's fixed cursor and the same bounded,
cancelable staging loop as `C-c C-o`.

Apply the snapshot and live presentation baseline immediately. Only the
missing prefix is staged. Automatic completion does not visit the prepended
range; manual pagination retains its existing jump behavior. Switching back
to a live buffer remains governed by [147](147-open-session-buffer-reuse.md),
and reconnect snapshots do not start a second automatic load.

## Why

A larger message cap cannot guarantee a complete long round. `turnWindow`
alone is insufficient because the message cap can still win. Sharing the
existing history request builder and fetch loop avoids separate cancellation,
error, cursor and viewport policies. Fetching before follow or staging live
frames until history finishes would delay output and complicate the gapless
stream contract without improving the requested history boundary.

## Consequence

Fresh chat buffers load the latest three rounds by default, including
subagent chats. `dsh-emacs-history-window` controls per-request messages, not
the final amount of opening history. `C-c C-o` can cancel automatic completion;
failed or canceled pages leave the visible tail and live output intact. Tests
cover bounded multi-page loading, draft position, live durable output,
subagent addressing, cancellation, reconnects, exhaustion and configured
follow request targets. This record accompanies the uncommitted change; the
existing follow framing commit above is historical evidence, not a claim
that this change has already been committed.

## Known limitations

A complete round means its start and all currently available events; an
active round does not have to finish before it is displayed. The initial
bounded tail can be partial while extra pages arrive. Cancellation or an RPC
failure leaves that tail visible, and manual pagination can continue from it.
Progress/completion messages describe only the additional rounds fetched.
Long rounds still require staging memory and multiple requests; legacy
history without turn boundaries is read to exhaustion, as in 110. Existing
character-based transcript trimming remains independent of round pagination.
