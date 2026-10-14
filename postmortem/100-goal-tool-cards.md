# 100 — Goal tool cards for create_goal / get_goal / update_goal

## Background

The three goal tools answered in the transcript as the generic ioCard: a
`Create Goal · …` header over the raw argument and result JSON.  dsh web gives
them a compact details card instead (`ui-tool`'s `detailsCardModel` →
`goalDetail`, registered for `create_goal` / `get_goal` / `update_goal`): the
objective as the row summary and expanded heading, then Status and Rounds, and
the blocker message while blocked.  The client already decoded the same goal
vocabulary for the Composer Goal Row (`dsh-protocol-goal`), so the information
was present but unread.

Two smaller gaps surfaced while wiring the card.  The `goal` variant had no
icon association, so the row kept the generic `others` sparkle rather than the
dartboard dsh web keys off the `_tool` suffix.  And `blockedReason` is a wire
`{code, message}` record, but the protocol struct stored the raw cell, so the
composer's tooltip and `C-c C-g ?` printed an alist while the card needed the
message.

## Decision

Render the three tools through one goal card in `dsh-emacs-render.el`:

- `dsh-emacs-tool-titles` gains `Create goal` / `View goal` / `Update goal`,
  and the new `goal` variant takes the Composer Goal Row's dartboard
  (`dsh-emacs-render--goal-trigger-icon`).  That dartboard and the Goal Row
  share `dsh-emacs-composer-goal-face`, retinted from the teal accent to the
  tool purple so a goal icon matches the tool row family everywhere (Goal Row,
  round notice, goal card).
- While the call runs the summary comes from the arguments — the objective, or
  `update_goal`'s action for its phase-only verbs, rather than the opaque
  `goal_id` the generic fallback would print.
- On success the result decodes through the protocol module
  (`dsh-protocol-goal-tool--from-alist`), which reads the GoalView core plus
  the process-local `activation` and the `roundsStarted` counter; the card
  shows the objective as its summary, then `Status` (including dsh web's
  `Awaiting continuation` for a disarmed active goal), `Rounds N / M`, and the
  `Blocker` message only while blocked.
- A cleared `{goal: null}` answer is the card's empty state (`No goal`, no
  fields, unfoldable), not a raw tombstone; an error or an unrecognized
  payload keeps the generic ioCard with its status line.
- `dsh-protocol-goal` carries `activation` and normalizes `blockedReason` to
  its human message in the shared constructor, so the projection and the tool
  value agree and the composer surfaces print the message too.

## Why

The card is a rendering concern and belongs in the renderer, next to the read,
diff, job, present and ask cards, but the goal *vocabulary* already belongs to
the protocol module — reusing `dsh-protocol-goal--from-alist` avoids a second
copy of `objective` / `phase` / `maxGoalRounds` and keeps the accessor surface
one struct wide.  Empty, error and malformed results falling back to the
existing ioCard keeps the "card models decline instead of signalling" rule the
other payload cards follow.

Normalizing the blocker in the protocol constructor was chosen over a
render-side `{code, message}` reader because two surfaces want the same
string; the code is machine-routable and has no client consumer today, so
carrying it bought nothing.  This is also the existing composer bug's fix, not
a new surface.

Rejected alternatives:
- **Parse the whole tool value in `dsh-emacs-render.el`** — duplicates goal
  field names outside the protocol boundary for no reader beyond this card.
- **Keep the generic ioCard and only relabel the title** — leaves the IN/OUT
  JSON as the body, which is exactly what web replaced.
- **Show `blockedReason.code` or the raw record** — the code names a policy,
  not the condition the reader needs.
- **Give the `goal` variant an entry in `dsh-emacs--variant-icons` /
  `dsh-emacs--tool-icon-svgs`** — would duplicate the dartboard SVG or move it
  out of the module that owns the composer row, for a tint the shared face now
  settles instead.

## Consequence

Goal tool rows read like dsh web's: objective summary, structured body, goal
icon.  Tests cover the settled create card, the pending update action, the
paused, blocked, disarmed and cleared states, the failed-call fallback, and
the protocol decoder.  `dsh-protocol-goal-blocked-reason` now returns the
message string for real wire data (string fixtures were already accepted), so
the Composer Goal Row's tooltip and `C-c C-g ?` stop printing an alist — a
user-visible fix recorded in `CHANGELOG.md`.  The `goal` variant has no icon
table entry by design; `dsh-emacs-render--tool-variant` resolves it through
the declared composer forward reference.

## Known limitations

The card is shown for a completed goal too, matching `goalDetail`; only the
composer's GoalBar hides `complete`.  `createdAt` / `updatedAt` and the
blocker code are dropped.  Round progress is the started count, not a
per-round history; the transcript trigger notice from
[099](099-goal-round-trigger-notice.md) carries that.

This records uncommitted work based on `c893b6b`.  Web source reference:
`deepseek-harness` commit `5badb15009`,
`packages/client/ui-tool/src/client/tool/models/details-card-model.ts`
\(`goalDetail`), `toolviews/details-row.tsx` and `tool/components/ToolDetails.tsx`.