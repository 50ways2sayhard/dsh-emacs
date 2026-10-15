# 101 — Next Message: Goal Row dock and inline queue actions

_Action availability and idle send-now safety are superseded by
[102](102-confirmed-queue-actions.md)._

_Goal Row background and action placement are superseded by
[103](103-compact-goal-row.md)._

## Background

Composer's Goal Row became a dock: a leading dartboard in its own tint face
(`dsh-emacs-composer-goal-face`), a prominent status label, a muted objective,
and the input-box background stretched across the row (`7e9b25b` aligned it
above the input; postmortem/099 and /100 retinted the glyph for the transcript
surfaces). The Next Message row — the pending-input preview from
[020](020-next-message-composer-region.md) — never got that treatment:
`dsh-emacs-composer--render-next-row` painted the whole line, its icon
included, with `dsh-emacs-input-prompt-face`, the bold accent that belongs to
the editable `❯` prompt; its non-SVG fallback was a bare `Next:` text prefix;
and acting on a pending message meant opening the `C-c C-q` manager and picking
a key against the highlighted entry. dsh web's queue row, by contrast, renders
the queue glyph beside a muted preview and ends its actions with
`IconSendOutlineRegular`, `IconEditOutlineRegular` and
`IconTrashOutlineRegular` — one click per verb on that row.

Two facts were missing behind the verbs. Our queue module's verbs are already
item-level (`dsh-emacs-queue--send-now`, `--edit`, `--delete`), so the row only
needed click targets; but a `dsh-protocol-queue-item` knew only its `id`,
`placement`, `text` and `kind`, so the row could not tell a text message from
one carrying an image or file block — and an edit sends text blocks back, which
would flatten that attachment. The failing layer is UI (Composer chrome); the
queue mirror, selection and repaint timing never changed.

## Decision

Dock the row like the Goal Row and give it a compact action cluster.

- **Dock**: `dsh-emacs-composer--next-icon` resolves dsh web's queue glyph
  (`IconQueueOutlineRegular`, the chat-bubble-with-two-lines artwork already
  embedded as `dsh-emacs-composer--next-icon-svg` but documented as a clock)
  tinted from the new `dsh-emacs-composer-next-face`; the folded preview
  renders in the new muted `dsh-emacs-composer-next-body-face`; the glyph keeps
  the Goal Row's two-column budget. Without SVG, it falls back to that tint
  face's `≡ ` instead of `Next:`. The row carries **no**
  `dsh-emacs-input-box-face` band: that face paints the Goal Row and nothing
  else, because the editable `❯` line deliberately holds no face at all.
- **Cluster**: one space after the preview text, cells one space apart in
  `steer · edit · delete` order, all in the new muted
  `dsh-emacs-composer-next-action-face`. Steer runs
  `dsh-emacs-queue--send-now` (steer while a turn runs, re-submit while idle);
  edit reads `read-string` prefilled with the current text and runs
  `dsh-emacs-queue--edit` (a blank answer is a no-op), and is present only
  while the item is `dsh-protocol-queue-item-text-only`; delete runs
  `dsh-emacs-queue--delete` with no confirmation. Each cell carries the item
  itself in a `RET`/`mouse-1` keymap, a hover highlight and a tooltip naming the
  manager key (`s`/`e`/`d`).
- **Fit**: `dsh-emacs-composer--next-cells` admits cells greedily while the
  preview keeps eight columns, so a narrow window drops the tail first
  (delete, then edit) and the arrow last; with no cell left the row is the bare
  preview.
- **Shared machinery**: `dsh-emacs-composer--goal-action-cell` became
  `dsh-emacs-composer--action-cell (glyph svg face help cmd)`, used by both the
  Goal Row strip and this cluster; `dsh-protocol-queue-item` gained the
  constructor-computed `text-only` slot; and `dsh-emacs-composer--sig` carries
  the next item's id, text and text-only flag, so a repaint can never leave a
  cell acting on — or offering the edit verb for — the item the row used to
  show.
- **Color ownership**: new `dsh-emacs-color-queue` / `-queue-dark` tokens hold
  the amber, and `dsh-emacs-modeline-queue-face` now reads them, so the
  Composer glyph and the mode-line `[Q2 S1]` indicator cannot drift apart.

## Why

Borrowing the prompt accent was the defect: `dsh-emacs-input-prompt-face` is
the editable prompt's identity (and `dsh-emacs-render--input-anchor-pos` scans
for its last run), so a read-only preview wearing it is wrong twice over. The
queue already has an identity color — the mode-line indicator's amber — so
"consistent colors" needs no new hue, only one owner. The Goal Row's muted body
face is the established tier for secondary text on the input-box background;
reusing the *tier* rather than the face keeps each row's ownership clear while
`next-body-face` and `goal-body-face` both inherit `shadow`. The glyph and the
\(absent) label are what dsh web ships: `QueueDock` renders
`IconQueueOutlineRegular`, and a single queued row carries no label, so none was
added.

Reusing the queue module's item-level verbs keeps one implementation per verb:
the row and the manager cannot drift into doing different things, and each
tooltip can name the manager key that does the same. `send-now` is deliberately
the arrow's verb rather than the raw steer RPC: it is the only verb correct in
both states, and it is what the manager's `RET` already runs. `text-only` is a
protocol fact, not a render-side guess — the wire `content` array is where block
types live, so only the decoder can decide it, and web draws the same line
\(`queue.edit.unsupported`). Deleting without confirmation is deliberate:
`d` in the manager and web's trash button both act at once, the cell is
deliberately muted and one space from the text, and a `y-or-n-p` would make the
inline path slower than the keyboard one.

Layout history: the arrow was first built right-aligned with the Goal Row's
`align-to` action math, then moved to sit one space after the text, then the
whole set was packed into the compact cluster recorded here — the owner's
reading is that these affordances belong to the message, not to the row chrome.
A very narrow window therefore drops cells from the tail instead of hiding one
right-aligned strip.

The band went the same way. Painting `dsh-emacs-input-box-face` across the row
was inherited from the Goal Row, but only that row ever used the face: the
editable `❯` line holds no face on purpose (`dsh-emacs--setup-input-area` marks
the prompt `rear-nonsticky` for `face`, so typed text cannot inherit half of the
prompt's colour), and no input box is drawn anywhere else. The band therefore
anchored to nothing — two dark strips over a light input line, the second one
mostly empty once the cluster became compact — and it carried no information the
tinted glyph and muted text did not already carry. It was removed, along with
the trailing `align-to` space that existed only to stretch it; the Goal Row
keeps its band, which is bounded by its own label/objective/actions.

Mechanism note (paid for once): the arrow artwork must carry `currentColor`, not
a color literal. The muted action tier resolves to the theme's `shadow` value,
and in the GUI that value is an X11 name (`grey70`) that librsvg does not accept
as a CSS paint — such a cell is in the buffer with a valid 13×13 image and a
working keymap, yet paints nothing. `currentColor` plus the image `:foreground`
is the only tint path here.

Rejected alternatives:

- **Right-align the action strip** (built first) — it read as unrelated row
  chrome and parked the actions far from short previews.
- **Paint the row with the Goal Row's input-box band** (built first) — it
  anchored to no input box, so it read as an unfinished rectangle; see the
  layout history above.
- **Tint the queue glyph or the actions with the goal purple** — purple is the
  goal's and the tool family's identity; the queue keeps its own amber and a
  muted action tier.
- **Add a `Next message` label to mirror `Ongoing Goal`** — the goal label
  states a status; the queue row has none, and web's single-row queue shows no
  label.
- **Reuse the goal faces for this row** — a queue preview is not goal chrome;
  the names would lie.
- **Offer edit for every item and rewrite attachments away** — silent data
  loss in the name of a smaller diff.
- **Confirm the inline delete** — inconsistent with `d`/web, and it would make
  the row's fastest path the slowest.
- **Call `dsh-emacs-queue--steer` directly** — wrong while idle (nothing is
  running to steer into) and it would need its own guard.
- **Render the cells only while a turn runs** — the row's shape would change
  with session state for a verb that has a correct idle meaning.
- **Bind new global keys for the verbs** — the cells are the item-specific
  affordance; `C-c C-q` already covers keyboard management of any entry.
- **Keep `Next:` as the fallback** — every other Composer row leads with a
  glyph (`◎ `, `▤`); a text prefix was the odd one out, not the icon.

## Consequence

The two Composer rows share one queue hue and one muted text tier — the Goal
Row keeps its dock band, the preview row carries none — so the preview reads as
a plain chrome line: the muted tier instead of the prompt accent, a glyph in
terminal Emacs, and the next queued message sendable, rewritable or droppable
from the row itself. Users get two new customization points
(`dsh-emacs-color-queue` / `-queue-dark`) and three new faces
(`dsh-emacs-composer-next-face`, `-next-body-face`, `-next-action-face`);
developers get one new protocol accessor
(`dsh-protocol-queue-item-text-only`) and the shared
`dsh-emacs-composer--action-cell` replacing the goal-only builder. The row no
longer carries `dsh-emacs-input-prompt-face`, which also removes a false
candidate from the input-anchor scan (never reached — the real prompt sits
closer to `point-max`). Docs touched: `docs/ui-styling.md` (faces table and the
row paragraph), `docs/architecture.md` (Composer section),
`docs/customization.md` (queue paragraph), `CHANGELOG.md` 0.6.0. Tests pin the
glyph/body/action faces, the icon's two-column budget in both glyph paths, the
queue color equal to the mode-line indicator's, the cluster geometry (one space
after the preview, cells three columns apart), each cell's verb and item, the
blank-edit no-op, the absent edit cell for a non-text item, the tail-drop
order, and the decoder's `text-only` for a content list with an image block.

## Known limitations

The row still previews only the next visible item, so every other entry stays in
the `C-c C-q` manager (postmortem/020); there is no queued count on the row.
Edit uses `read-string` in the minibuffer rather than web's inline editor, so
the row is momentarily left (an Emacs-idiomatic trade); attachments are
preserved only in the sense that the edit cell is withheld — no edit path keeps
them. Delete does not confirm, and steering an item already `steering` reports
`Already steering` through `send-now` rather than disabling the cell. Cells are
dropped together with the arrow in a window too narrow for eight preview
columns. `dsh-emacs-color-queue` covers the Composer glyph and the mode-line
indicator only — any later queue surface must read the same token to stay
consistent. The prior record's `Next:` fallback and "clock" reading are
superseded here.

This records uncommitted work based on `79cadfd`.
