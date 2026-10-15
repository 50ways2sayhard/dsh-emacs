# 104 — Automatic compaction has a summary and an activity caption

## Background

At `e8cf554`, protocol and mode-line code tracked compaction start/end, but
the renderer discarded `compaction/summary`. Automatic compaction left no
readable evidence unless it failed, and its separate `Compacting` label
competed with the running `Deep diving` caption. Record 070 deliberately
kept successful compaction transient. The missing summary belonged to
protocol/render consumption; the existing event stream already delivered it.

Host evidence is `deepseek-harness` commit `5badb15009`,
`packages/compaction/compaction-basic/src/region.ts`:
`commitCompactionBody` appends the summary before applying the replacement
checkpoint. Its `shadowedTokenCount` sums heuristic tokens of the selected
old context, and `shadowedSeqs` enumerates its surface items.

## Decision

Decode a typed compaction summary in protocol and render an automatic one as
a folded **Automatic compaction** row, with expandable Markdown summary,
history-item count and approximate old-context tokens. Preserve the original
conversation and hide the raw model output and replacement checkpoint body.
Suppress manual summary events with a source command id; the existing
`/compact` card keeps its counts and result or failure text.

Use the existing Motion Line activity slot for teal `Compacting` and its own
local elapsed clock, including between turns. Preserve the underlying turn
clock and restore `Deep diving` afterward. Retry and Plan remain independent.
Without Motion Line, show static `Compacting`. This records uncommitted work
against `e8cf554` and supersedes only 070's compaction presentation decisions.

## Why

The summary is useful retained context, but its presence does not prove that
checkpoint application succeeded. Neutral wording permits a later automatic
failure card to coexist without contradicting a success claim. The count
describes history items, not conversational messages, and the token estimate
describes the old context, not savings or remaining capacity.

A compact folded row makes the event visible without replacing the user's
conversation with a model-facing checkpoint. A stable compaction id prevents
duplicate rows during replay. Keeping manual command output in its existing
card avoids presenting the same operation twice.

Compaction is the activity the user is waiting for, so it takes the whale's
caption instead of adding another competing label. Sharing the existing slot
and scheduler avoids another timer; a separate observation timestamp preserves
the enclosing turn's elapsed duration through the phase change.

## Consequence

The transcript records automatic summaries and failures separately. Native
and Doom mode lines use the same compacting activity, with
`dsh-emacs-modeline-compacting-face` and
`dsh-emacs-modeline-compacting-highlight-face` controlling its teal caption
and sweep. No new option or keybinding is added. README, mode-line, RPC,
architecture and styling documentation describe the surfaces and their limits.

## Known limitations

Follow/history windows are bounded. A missing summary produces no summary
row, and a missing start cannot reconstruct live compacting status. Fetching
or caching extra compaction history is deliberately deferred: these surfaces
reflect the events already available to the client. The compaction clock is
local observed time, so reconnecting or reopening starts a new interval;
repeated snapshots of the same active compaction preserve it. Pruning events
still have no dedicated transcript renderer.
