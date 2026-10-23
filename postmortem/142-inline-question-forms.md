# 142 — Questions and approvals answer in the Composer, not the minibuffer

## Background

Every `ask` question and every approval was answered through the minibuffer.
The reader built in [042](042-question-prompts.md) did one
`completing-read`/`completing-read-multiple` read per question, and approvals
asked `y-or-n-p`. Both were called synchronously from the `$events` process
filter, so the filter blocked until the user answered, and only one prompt
could exist in Emacs at a time ([124](124-shared-interaction-owner.md) gave
the two queues one owner to make that visible). Three user-visible failures
followed:

- a question from one session interrupted whatever the user was typing in
  another, because the minibuffer is a global resource and question/approval
  arrivals were served in queue order, not by focus;
- abandoning the read (`C-g`, a reader error, a frontend that refused to open)
  declined the whole waterfall, so a dismissed prompt silently aborted the
  agent's `ask` instead of leaving it answerable;
- parallel task flows could not proceed while a prompt was open, and a timed
  question that expired behind another session's prompt had no answer path
  until [073](073-timed-question-answers.md) added the late-answer command,
  which itself opened another reader.

The user asked for requests to live in their own buffer and stay visible and
answerable at any pace, without a prompt interrupting the conversation.

## Decision

Render `user-questions/request` and `approval/request` waterfalls as read-only
forms in the owning chat buffer's Composer chrome, directly above the `❯ `
input line, and answer them from the input line; remove the synchronous
minibuffer readers entirely.

`dsh-emacs-interaction.el` owns the state and the rendering. Each chat buffer
keeps its own `dsh-emacs-interaction--requests` list (oldest first), its
`userQuestions` projection mirror `dsh-emacs-interaction--session-questions`,
and a bounded `dsh-emacs-interaction--retired` id set so a replayed waterfall
cannot reopen an answered form. `dsh-emacs-composer.el` keeps owning the
chrome region and asks the module for the form rows
(`dsh-emacs-interaction--chrome`); the rows sit below Next Message, the Goal
Row and Attachments and immediately above the input. The entry point
`dsh-emacs.el` no longer owns a prompt loop: `dsh-emacs-events.el`'s
waterfall branch routes a frame to `dsh-emacs-interaction--question-requested`
or `--approval-requested` after plan review has declined it, and
`dsh-emacs-send-or-stop` asks `dsh-emacs-interaction--submit-pending` before
sending.

A form is a title row (`? Question 1/2 · header` via Nerd Font help-circle when available, or `…` while submitting),
the question text, its muted detail, one option cell per option
(`1 src/   2 test/`) and a hint row; an approval shows `⚠ Approval · tool`,
the call's command line, the localized reason, and `Allow once` / `Reject`
cells. Cells carry `dsh-emacs-interaction-cell-keymap`, which binds `RET`,
`return`, `mouse-1` and `mouse-2` to `dsh-emacs-interaction-activate`; a
single-select option cell answers at once, a multi-select option cell toggles
its number in the draft for a later `C-c C-c`, and approval cells decide at
once. The draft text is the answer field: `dsh-emacs-interaction--interpret`
maps empty text to a skip, numbers/labels (resolved by
`dsh-emacs-interaction--resolve-options`) to those options, and anything else
to a custom answer; `dsh-emacs-interaction--make-answer` builds the
`dsh-protocol-question-answer-request` payload. `dsh-emacs--clear-input`
empties the field between questions of one batch, and `--advance` sends the
whole batch as one outcome after its last question.

Only the oldest question form owns the input line; it is always rendered, up
to `dsh-emacs-interaction--max-forms` (3) requests get full rows, the rest are
named in one summary line, and approvals are decided by their own cells in
any order. Live answers post `$events/result` through
`dsh-emacs--events-result-async`; a question batch declines with the
`rejected`/cancelled outcome ("User abandoned the questions") so the host
aborts its `ask` instead of waiting, and a late form is dismissed locally.
Timed questions keep their window with a `userQuestions/attachWait` stream
(`--claim`), and when that claim is gone or the window closed they become
`late` forms (`--materialize-late` from the projection's `continued` calls)
that submit through `userQuestions/answer`. `M-x dsh-emacs-answer-question`
(`C-c C-p`) still exists but now materializes late forms and calls
`dsh-emacs-interaction-focus` instead of reading.

Removed without aliases: `dsh-emacs-question-skip-key`,
`dsh-emacs-question-help-display`, `M-x dsh-emacs-question-preview`, the
whole reader (`dsh-emacs--question-reader-setup`, `--question-choice`,
`--collect-question-answers`, the crm path), the queues
(`dsh-emacs--question-queue`, `dsh-emacs--approval-queue`), the prompt owner
(`dsh-emacs--interaction-active`, `--interaction-drain`) and the approval
prompt (`dsh-emacs--approval-prompt`). New commands:
`dsh-emacs-interaction-decline` (`C-c C-k`), `dsh-emacs-interaction-allow`,
`dsh-emacs-interaction-skip` and `dsh-emacs-interaction-focus` under the
`C-c C-u` prefix (`a` allow once, `d` decline, `s` skip, `f` focus).

## Why

- **The request must survive the read.** A minibuffer read is a synchronous
  global transaction: its exit path decides the whole waterfall, so any
  dismissal is an answer. Making the form a buffer-local data structure
  removes the decision from the exit path — a form is answered only by an
  explicit command, and stays pending across window switches, buffer
  switches, and long working pauses.
- **Parallel sessions need per-buffer requests.** One prompt slot serialized
  question and approval service across every live session
  ([124](124-shared-interaction-owner.md)); per-chat-buffer lists make
  simultaneous pending requests representable instead of something to drain.
- **The draft is already the natural answer field.** `C-c C-c` is the send
  key the user presses anyway; answering a question with it keeps one
  gesture, one field and one place for multi-line or free-text answers,
  instead of a second text-entry surface in a popup.
- **Parity with dsh web.** The web client shows the ask panel in its
  composer, option rows clickable and the answer typed below; matching that
  shape keeps the two clients recognizable and reuses the existing ask-card
  rendering for settled answers.
- **One outcome per batch.** Numbers/labels/custom text resolve to the
  protocol's answer documents in the interaction module, so the question
  semantics moved out of the minibuffer UI without changing the wire format
  (`dsh-protocol-question-answer-request` stays the encoder).
- Rejected: an asynchronous minibuffer (`minibuffer-with-setup-hook` +
  idle timer). It still owns the single global minibuffer, still needs a
  non-blocking key-loop design, and still reads like an interruption —
  exactly what the user reported. Rejected: a dedicated question side
  window or popup frame. It steals focus from the conversation and needs its
  own navigation, sizing and dismissal rules; [042](042-question-prompts.md)
  already rejected a dedicated side window for the same reason. Rejected:
  keeping the minibuffer as a fallback for chats whose Composer cannot
  render. A second answer path doubles the state machine for a case that is
  already handled by handing the waterfall back to the host
  (`$events/result` outcome `next`).

## Consequence

New user surface: the Composer form rows; `C-c C-c` answers a pending
question instead of sending (a prefix argument still sends the draft);
`C-c C-k` declines the oldest request; `C-c C-u a` allows the oldest approval
once, `C-c C-u d` declines, `C-c C-u s` skips the current question and
`C-c C-u f` moves point to the input line. `C-c C-p`
(`dsh-emacs-answer-question`) keeps answering expired timed questions but
renders a late form and focuses the input line instead of reading. Desktop
notifications still announce arrivals; plan reviews keep their special
`*dsh Plan:` buffer and bypass this module; approval reasons keep the
localized selection from [074](074-localized-approval-reasons.md).

Removed: `dsh-emacs-question-skip-key`, `dsh-emacs-question-help-display`,
`M-x dsh-emacs-question-preview` and the internal reader/queue/owner symbols
listed above. `M-x dsh-emacs-reload` now refuses while any chat buffer holds
an unanswered form (`dsh-emacs-interaction--pending-p`) instead of checking
the old interaction owner.

Connection lifecycle keeps its old guarantees in the new shape: a chat killed
with live waterfalls answers each with outcome `next` (another client may
claim it), a reconnect retires forms from the previous `$events` generation
because their event ids cannot be answered with the new client id, and a
withdrawn waterfall retires the matching form. The `userQuestions` projection
remains the only source for late answers, and settled calls complete their
ask card through `dsh-emacs-render-question-settled` unchanged.

Docs in the same change: this record, `CHANGELOG.md` (0.7.0 Breaking Changes
and Added), `README.md`, `docs/architecture.md` (module map and the
interaction section), `docs/customization.md` (question and approval
workflows, keys, removed options), `docs/rpc.md` §11.1 and the question
mentions in `docs/slash-commands.md` and `docs/ui-styling.md`. Tests move from
reader mocking to form state: they assert rendering, option staging, answer
resolution, batch submission, decline/allow/skip, late forms, replay dedupe,
generation retirement and the reload guard.

Implemented as an uncommitted working-tree change on `6622e8c`; there is no
commit for this record yet.

## Known limitations

- **One owning question form per chat buffer.** Only the oldest question owns
  the single draft; later questions wait as one-line summaries (and beyond
  three forms the middle ones are elided), so a batch of questions is
  answered strictly in order.
- **The input line doubles as the answer field.** A draft typed before the
  question arrived is read as its answer — there is no draft stash — so a
  pending form changes what `C-c C-c` does to existing text. Approvals are the
  exception: their cells decide, and `C-c C-c` still sends the draft.
- **Timed requests degrade to late answers.** A form whose `attachWait` claim
  was lost (reconnect, chat reopened, window closed elsewhere) cannot be
  answered through `$events/result`; it becomes a `late` form and submits
  through `userQuestions/answer`, whose acceptance rules are the host's
  (root agent, every question answered exactly once, no already-queued
  reply). A rejected late batch returns the form instead of reporting
  success.
- **No minibuffer fallback.** A frame with no live chat buffer, no event id,
  or an unreadable payload is handed back with outcome `next`; nothing in
  Emacs answers it. The form is also the only in-Emacs UI: there is no
  `completing-read` path left to use from another buffer or from Lisp.
- There is no countdown on a timed form; the row says `window closed — answer
  late` once the projection reports `continued`, matching
  [073](073-timed-question-answers.md)'s single-frame claim.
