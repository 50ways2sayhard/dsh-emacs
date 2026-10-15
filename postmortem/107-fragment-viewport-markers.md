# 107 — Fragment updates keep window starts as markers

## Background

`dsh-emacs-ui-update-fragment` (UI layer) has saved `window-start` as an
integer and restored it after every changed write since the initial import
(`df93cd5`). It also asked only `get-buffer-window` for one window, and
decided "at the bottom" by counting logical lines with `forward-line`.

A probe with the window starting at `filler 40` below a 10-line card showed
the cost: growing the card by five lines moved the view to `filler 35`;
shrinking it left the start in the middle of a line (`er 46`). Any card
updating above a scrolled-up reader — tool, job, subagent, a fold toggle —
shifted the text the reader was looking at. Other windows on the same buffer
were not considered. The renderer had already replaced logical-line counting
with screen rows and native `recenter` ([031](031-stream-frontier-and-screen-rows.md),
[037](037-streaming-display-cpu.md)), so two following policies coexisted.
Older-history loading only looked correct because its caller wraps the
render in `save-window-excursion`.

The comparison came from ETAF's
[incremental update and publication](https://etaf.top/zh-cn/incremental-updates-and-publication/)
design: the write tracks each window's point and start through replaced
lines, and scroll decisions happen once geometry is stable.

## Decision

The write layer no longer restores a saved start. Emacs already keeps each
window start as a marker, so it moves with text edited above it. After a
changed write, for every window showing the buffer:

- a window whose view reached `point-max` before the write is recentered on
  `point-max` with `recenter -1`, then its start is re-set unforced;
- a start that was at a line beginning and is no longer (it collapsed onto
  the replaced span) moves to that line's beginning;
- every other start is left alone.

The screen-row bottom test moved from the renderer to the UI module as
`dsh-emacs-ui--window-at-bottom-p`; stream following now calls it there.
Windows are measured only after both "nothing to write" early returns, so
cache hits do no viewport work: 2000 identical updates took about 9 ms,
against 19 ms with the old unconditional `forward-line` measurement and
53 ms when the new screen-row measurement ran before the cache check.

## Why

The integer restore was compensating for nothing: marker movement is the
behavior readers expect, and restoring a number undoes it. Snapping only
starts that changed from line-beginning to mid-line confines the correction
to the collapse case, so a start legitimately inside a wrapped line is not
pulled to its logical line start. Re-setting the recentered start unforced
keeps the old point semantics: redisplay may still scroll to point instead
of moving point, as before. One bottom predicate removes the divergence
between UI and renderer.

Rejected: moving all following out of the UI into a single per-dispatch
flush. Many update callers do not end with `dsh-emacs-render--follow-stream`
(spinners, session/job cards), so bottom-following would regress for them.
A batch measurement of 800 card inserts showed the per-update viewport work
costs about 2 ms in total, which does not justify that restructuring now.

## Consequence

Cards changing above the visible text no longer move it, in every window.
Following windows stay pinned, measured by screen rows, so a long wrapped
line no longer makes a scrolled-up reader look "at the bottom". New tests
cover growth/shrink with two windows, a start inside the replaced span, a
reader above a wrapped line and a following window. The architecture doc
describes the rule.

## Known limitations

A window whose start equals the first retained suffix character of a
replaced span ends up before the inserted text (marker insertion type nil);
the reader then sees the changed lines first. Older-history loading still
wraps its render in `save-window-excursion`; that compensation was left in
place. The GUI behavior was checked by batch probes and unit tests, not yet
in an interactive session.
