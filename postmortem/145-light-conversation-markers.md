# 145 — Use light conversation markers and an inline reply footer

Prompt retention is superseded by [146](146-user-message-copy.md).

## Background

Task folding from [142](142-task-work-details.md) made completed work
compact, but conversation boundaries still read poorly: an answer group could
contain a full-width divider, completion time appeared above and below the
answer, and the next human message could touch the preceding footer. The
render/UI layer owned these visual boundaries; transport and turn identity
were sound.

An earlier pass painted a full-width user-message background, requested two
blank lines before each question, and right-aligned trailing footer
statistics. Reviewing a screenshot, the user found the band resembled a
selected editor line and the spacing excessive; the summary also touched the
answer and the footer competed with the content. After comparing two
previews, the user selected the light-marker design.

## Decision

Replace user-message backgrounds with a thin left rail, keep theme
typography, and give each question one blank line above. Remove the task
disclosure's separator body and add half-line spacing below completion
summaries on graphical displays.

Keep the shared reply metadata face and the `(copy fork usage)` footer
default, with `duration` opt-in. Render every footer item together on the
left in `dsh-emacs-reply-footer-items` order, separated by dots, instead of
aligning trailing statistics to the window edge.

## Why

A rail identifies the speaker without painting a full-width band or narrowing
long questions into a bubble. Emacs line/wrap prefixes preserve real message
text, navigation, copied text, and automatic wrapping; see
[146](146-user-message-copy.md) for keeping historical text free of prompt
decoration. One blank line separates turns without the excessive space above
the rail.

The summary's newline owns its extra spacing, so no extra card or spacer body
is needed. A disclosure belongs to its answer, so an internal dividing rule
worked against that relationship. Reusing the existing message insertion and
fragment owners keeps history, optimistic echoes and live messages on the
same layout path. Inserted message spacing carries the transcript boundary so
history cannot slip between it and the task start. Footers own a trailing
blank row so late history footer insertion keeps the gap before the next
question.

Footer items stay together because the short row reads as one compact unit:
with duration omitted by default, a right-aligned single Tokens item looked
detached. Inline order directly reflects the configured sequence and removes
the trailing-statistics counter and stretch space.

## Consequence

`dsh-emacs-user-block-face` no longer supplies a background. The new
`dsh-emacs-user-border-face` controls the three-pixel graphical rail.
Terminals use a muted vertical glyph and ordinary line spacing. Summary,
chevron and footer text use `dsh-emacs-reply-meta-face` at normal weight.
Copy/Fork targets and per-turn statistics are unchanged. README, styling,
customization and architecture docs describe the result; the
[0.7.0 changelog](../CHANGELOG.md) records this uncommitted change based on
`1dcdb5d`.

## Known limitations

Existing transcript buffers require reopening after reloading to rebuild
prefixes and footer strings. Narrow windows retain the fragment renderer's
existing label truncation; label fitting is recomputed when the row updates.
Typography remains theme-owned.

With folding disabled or an ineligible turn, default footers no longer show
elapsed time; add `duration` to `dsh-emacs-reply-footer-items` to keep it
visible. Explicit user footer settings remain respected, including a
configured `duration` item.
