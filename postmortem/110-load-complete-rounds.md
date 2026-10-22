# 110 — Load complete rounds, with visible boundaries

Opening-history policy superseded by [148](148-open-complete-rounds.md):
fresh chats now use the same complete-round target and bounded loader.

Display refinement: round headings were subsequently removed at the user’s
request; round numbers remain only in the completion message.

## Background

The work following `98ac701` fixed viewport stability, but record 109's
previous/next loaded-question commands duplicated Imenu. The user clarified
that the problem was knowing what history had been loaded, and requested
loading several complete rounds at a time, for example the previous three.
Message-count pagination gave no reliable indication of that progress.

## Decision

Remove the uncommitted previous/next question commands and keys. Keep Imenu
(`M-x imenu`, with no keybinding of its own), independent reading windows and
the return-to-draft command. Make `C-c C-o`
load three complete earlier server rounds by default; a numeric prefix
selects another count. A partial oldest round counts as the first one to
complete. Report the actual loaded range and count in the completion message;
the visible `Round N` headings added first were removed at the user's request
(see the note above).

The protocol layer decodes history boundaries and serializes `turnWindow`.
Each RPC remains bounded by the existing message batch size. The history
controller stages records until enough starts arrive or history is exhausted,
then prepends the range once. Repeating the command cancels the operation;
failed or canceled fetches do not advance the pagination frontier. Request
identity rejects late responses, and monotonically decreasing cursors prevent
an endless request loop on a repeated page.

After loading, the initiating window visits the oldest newly loaded round,
saving its old point in the mark ring. This happens only if that window is
still selected and its point has not moved while waiting. Other windows stay
on their text. The viewport preservation and following policy from 109 remain.

## Why

Round boundaries express the amount of conversation the user wants to load.
Increasing `maxMessages` alone cannot guarantee a full long round, and
`turnWindow` alone can still stop at the message cap. Continuing bounded
requests is necessary to make the completeness promise true. Staging avoids
committing a partial round before a network error or cancellation.

Visible round headings and automatic positioning let the user inspect what
arrived immediately. Adding more navigation keys did not answer that question,
so those commands are removed rather than retained as another workflow.

## Consequence

`dsh-emacs-history-rounds` controls the default count. `dsh-emacs-history-window`
now describes opening history and per-request message limits only. A completion
reports the actual count when fewer rounds remain. RPC, renderer, unit tests,
GUI tests, README and customization docs share this contract. A read-only
real-server replay loaded rounds 2–4 in seven bounded requests, keeping the
live frontier at seq 1415.

## Known limitations

A round is the server's turn boundary, including autonomous continuations,
not necessarily one visible user question. Historical data without boundary
records is loaded to exhaustion and explicitly reported without round counts.
A long requested range can use substantial staging memory and take multiple
requests; cancellation is available between responses. The request count is
bounded by the session's length rather than by a fixed cap — a very small
`dsh-emacs-history-window` multiplies round trips, which is why the loop
reports progress and stays cancelable instead. Cross-page search and
random access by round number are not part of this change. The pre-existing
character-based trimming/frontier limitation noted in 109 is unchanged.
