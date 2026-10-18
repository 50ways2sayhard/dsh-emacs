# 121 — Distinguish attempt outcomes in the transcript

## Background

At `58d6e2e`, retries appeared in the mode line while uncommitted output
appeared in an Attempt card. The user asked for one transcript presentation
with consistent styling and explicit retry/error distinctions. The wire
already supplies the required facts; the missing correlation belongs in render.

## Decision

Remove mode-line retry state and labels. Keep the existing attempt fragment,
its live-stream takeover, folding and tool-row styling. Decode terminal reasons
alongside retry facts in protocol; render joins them by turn, step and sequence.
Retries consume the preceding unresolved attempt. A started transition matches
the retry id and number; terminal error/cancellation settles only the remaining
unresolved attempt. Cancellation during backoff says Retry cancelled.
Compaction recovery can return a retry decision without emitting `llm/retry`.
A later attempt or committed response in the same turn and step proves that
the preceding attempt was retried: label it Retried without a fabricated count.

Store the small decoded facts by turn and sequence, allowing an older page to
complete an outcome pair. Update full fragment snapshots in place, preserving
user folding and partial output. Track the newest event's transcript boundary
per turn and release facts when trimming consumes that boundary. Retain facts
for visible turns even if their attempt cards are on an older page; prepending
that page must not move the boundary backwards. Failure details live on hover; final turn
errors retain their own explanatory row. Model errors, retry/cancellation
cards and automatic compaction failures share a status dot, the tool title
face and compact spacing. Retry is orange, failure red, cancelled/unknown grey.
Normal automatic compaction summaries retain their existing terminal icon.
Error codes become muted metadata; explanations remain expanded initially.

This records uncommitted work following `58d6e2e`, superseding the retry
presentation in [070](070-execution-feedback.md) and the attempt-card title
in [040](040-core-event-rendering.md).

## Why

`assistant/attempt` has only turn, step and stream. A neutral title alone would
hide the distinction the user needs. The subsequent retry and turn-end events
supply evidence without changing dsh or guessing from output text. The producer
reuses a turn/step across retries, so a single status per step would incorrectly
apply the final failure to earlier retried attempts. Ordering and exact retry
identity avoid that mistake. Stored scheduled waits are historical facts, not
a local countdown requiring timers.

The initial terminal icon reused tool chrome but suggested a shell operation.
Upstream dsh 0.2.1-rc.2 `ui-chat/src/client/chat/MessageItem.tsx` uses an error
`StateDot` for terminal failures; retry has text and a disclosure chevron, no
leading icon. Use that status-dot vocabulary consistently for exceptional
events in Emacs. A small SVG circle uses existing status faces, with a `●`
terminal fallback; explicit titles keep meaning independent of color.
GUI verification caught that Emacs/X11 names such as `red1` are not valid SVG
colors, so face colors are resolved to RGB hex. Cancellation uses the timestamp
face: comment-derived muted text can be red in the default Emacs theme.
This changes the icon choice without introducing another asset registry.

## Consequence

One compact card shows Retry (scheduled/started), Retried, Failed reply, Cancelled reply
or Retry cancelled. Native and Doom mode lines retain running, compaction and
Plan feedback. No command, option, face, keybinding or polling loop is added.

## Known limitations

Incomplete reply remains when the outcome has not arrived, has been truncated
from the retained history, or uses an unrecognized terminal reason. Missing
evidence is not classified as failure. Hover exposes retry failure details;
the existing body continues to contain only the model's partial output.
