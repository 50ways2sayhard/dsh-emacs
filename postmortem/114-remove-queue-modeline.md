# 114 - Keep the pending queue in the input area

## Background

At `d96a449`, pending input had a Composer Next Message preview with inline
controls, the `C-c C-q` manager, and a live `[Qn Sm]` mode-line count.
[003](003-queue-steer-host-snapshot-mirror.md) introduced the count before
Composer owned the preview; [064](064-inbox-projection-queue.md) moved the
mirror to the inbox projection, and [101](101-next-message-goal-dock.md)
added inline actions and shared queue colors. The user requested removing
the duplicate mode-line surface, as with background jobs in
[088](088-remove-job-modeline.md).

## Decision

Remove the queue segment from the shared native/Doom mode-line composition.
Delete its indicator, cache, mouse keymap, public face
`dsh-emacs-modeline-queue-face`, and queue-only mode-line redraws. Keep the
queue mirror, counts, `C-c C-q` manager, echo feedback, queue/steer semantics
and Composer previews. Keep `dsh-emacs-color-queue` and
`dsh-emacs-color-queue-dark` for the Composer Next Message glyph.
This record accompanies uncommitted work based on `d96a449`; that commit is
the baseline, not the removal commit.

## Why

The input area owns pending-message presentation and inline actions;
`C-c C-q` owns whole-queue inspection and management. A separate mode-line
count spends space on the same queue without enough value to justify its
cache, mouse shortcut and redraw work. The mirror and its counts still have
real consumers, so removing the display must not remove queue state.

A new visibility option would retain an unwanted surface and its maintenance
cost. Remove it outright rather than adding a toggle or compatibility alias.

## Consequence

Queue management remains available through `C-c C-q` or
`dsh-emacs-list-queue`; its prompt retains queued and steering counts.
Composer still previews the next visible item in delivery order and offers
confirmed-item actions. Existing theme customizations for the removed face
must be deleted; the queue color options still style Composer. No new option,
command or replacement mode-line segment is added.

## Known limitations

Queue counts are no longer passively visible in the mode line, including
when the input area is off screen. Composer previews only the next visible
item, not the full queue or its counts. This is accepted: `C-c C-q` remains
the on-demand route to the whole queue and its counts.
