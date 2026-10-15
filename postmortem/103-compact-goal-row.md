# 103 — Compact Goal Row on the buffer background

## Background

[101](101-next-message-goal-dock.md) removed the Next Message background band
and placed queue actions directly after the preview. Goal still stretched a
background across the row and parked actions at the right edge. The user
requested the same background and compact button placement for Goal.

## Decision

Use the buffer background and place the existing goal action strip one space
after the objective, retaining its one-space separators. Remove the trailing
stretch padding and the now-unused input-box face and its two color options.
The goal's purple dartboard, status label and muted objective/actions retain
their own faces.

## Why

Short objectives should keep their controls nearby. A full-width background
adds an isolated band above an editable input that has no such background.
Removing the last consumer also removes obsolete customization definitions
rather than leaving settings that silently do nothing.

## Consequence

Goal and Next Message now have consistent backgrounds and compact actions.
Existing goal commands, tooltips, pending labels and action visibility remain
unchanged. The removed customization names are documented as a 0.6.0 breaking
change. This record accompanies the uncommitted Goal Row layout change
following 101.

## Known limitations

Goal keeps its existing all-or-nothing action-strip fit rule, preserving eight
objective columns; Next Message drops individual trailing cells. This change
only synchronizes the normal layout. Hidden goal actions remain available
through `C-c C-g`.
