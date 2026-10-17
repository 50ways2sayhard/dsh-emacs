# Mode-line Status

The major-mode label uses the DeepSeek Harness whale SVG with its vertical
padding cropped to match the permission shield's visible height, without
making the mode line taller or adding a badge or background. In native mode
lines, it stays in the major-mode cluster. With Doom Modeline, the larger mark
appears just before `buffer-info`, beside the buffer name, and the DSH Web
running-status whale tail appears in the right-side major-mode slot. During an
active turn, graphical Emacs with Motion Line and GIF support displays the web whale's
60-frame, 28-pixel animation with 50ms per frame and a three-second loop.
Both the running GIF and idle SVG use an 18×18 display box with a centered
baseline. The larger box makes the tail clearer despite its transparent
padding. The optional `motion-line` package selects GIF frames
explicitly; mode-line evaluation starts no timers. Both tails use the logo's
color: blue (`#4d6bfe`) on dark frames and black on light frames, including
Doom's right-side tail. Theme changes update running frames on the next
visible tick.

[Motion Line](https://github.com/vritser/motion-line) is an optional dependency,
installed separately. Install `motion-line.el` with `M-x package-install-file`,
or add its checkout to `load-path` before loading dsh-emacs:

```elisp
(add-to-list 'load-path "/path/to/motion-line")
(require 'dsh-emacs)
```

When Motion Line is unavailable, dsh-emacs loads normally and displays static
`Deep diving` text during a turn, or teal `Compacting` during context
compaction, in both native and Doom mode lines. The text has no whale
animation, sweep or elapsed clock and creates no animation timer. It
disappears when both activities finish or on disconnect. Step, Plan and
execution feedback keep their existing behavior; step elapsed text refreshes
only when Emacs otherwise redraws. No bundled copy or automatic download is
needed. Restart Emacs after installing Motion Line to enable animation.
Errors inside an installed library still surface normally.

The following animation and clock details apply when Motion Line is installed.

When idle, Doom uses the same static SVG path as the web runtime's fallback.
The native running indicator disappears. Terminals and builds without GIF
support use cycling `DSH.` / `DSH..` / `DSH...` text while running; the idle
label is `DSH` without SVG. The larger whale logo remains blue (`#4d6bfe`)
on dark frames and black on light frames. Emacs does not decode APNG; the
converted GIF retains its motion and timing but uses binary transparency.
Its Base64 data is embedded in `dsh-emacs-modeline.el` and decoded on first
use, then cached; installations need no external image file.
See [asset provenance and conversion](../assets/dsh-whale-tail.md).

While running, the tail is followed by `Deep diving · 12s`. The English
caption uses a gentle foreground sweep over a three-second cycle in graphical
Emacs, with a quiet gap between passes. The duration updates in whole seconds,
using `1m05s` after a minute. Terminal captions remain static beside the cycling
text indicator. Whale, caption and clock share the existing animation slot;
Doom retains the sweep's text properties. Its ordinary running and idle
states keep the standard major-mode menu; clicking `Compacting` opens status
details instead.

The clock starts at `0s` when this buffer enters the running state. It measures
local observed running time, including tools and waits; it is independent of
the three-second animation loop and does not reset on repeated running
snapshots. Turn completion and disconnect clear it. A reconnect or reopening
a session starts a new local observation interval, rather than claiming an
exact server turn duration. For completed turns, the reply footer retains the
server-based duration. See [095](../postmortem/095-running-status.md).

Customize `dsh-emacs-modeline-running-face` for the caption/clock foreground
and `dsh-emacs-modeline-running-highlight-face` for the sweep's peak color.
Setting both foregrounds to the same color removes the text sweep.
Compaction uses `dsh-emacs-modeline-compacting-face` and
`dsh-emacs-modeline-compacting-highlight-face` for the same roles, with teal
defaults. See [Execution feedback](#execution-feedback) for its separate clock.

The stats use `dsh-emacs-modeline-format-spec` to choose segments and their
separator (one space by default). Status indicators—animation, Plan/retry
and subagents—and the parenthesized stats have one separating space in
both native and Doom mode lines. Empty indicators add no gaps; SVG placeholders
retain their display and click properties. Doom's right-side major-mode slot
shows the DSH Web runtime whale mark in DSH chat buffers. Ordinary running and
idle states retain the standard major-mode menu; `Compacting` opens status
details. Custom Doom layouts with `buffer-info` and `major-mode`
anchors receive the same segments. Reopening chats does not duplicate them,
and Doom's excluded layouts remain excluded.

Available stats segments:

- **cwd**: current working directory (home path abbreviated with `~`)
- **branch**: git branch name (auto-detected)
- **provider**: provider id serving the model (e.g. `deepseek`), opt-in — the
  provider also rides the model segment's tooltip
- **model**: current model name (fed live from `request/header` / `request/context`)
- **effort**: reasoning effort — the `reasoningEffort` chosen via the model
  picker, or the one the host announces in `request/header` (e.g. `high`)
- **preset**: agent preset of the session (`agentPreset`, e.g. `standard` / `code`)
- **permission**: the `permissions` session projection's current value, drawn
  as a shield icon so it costs one cell: the dsh-web SVG shield (check =
  `read-only`, pencil = `workspace-write`, exclamation = `danger-full-access`)
  in graphical Emacs with SVG, otherwise the matching Nerd Font shield glyph
  when `nerd-icons` is installed, otherwise a short token. An unrestricted
  session (or the derived `custom`) tints the shield with
  `dsh-emacs-modeline-permission-warn-face`; the tooltip carries the full
  preset name. No emoji are used — they are double-width and ignore the face
  color. Switch it with `M-x dsh-emacs-set-permission` (see
  [Customization](customization.md#permission-presets)); set
  `dsh-emacs-modeline-permission-style` to `text` for the unabbreviated name
- **tokens**: token usage (`↑input ↓output Rcache-read Wcache-write CHcache-hit%`)
- **ctx**: context-window usage percentage (color-coded)
- **cost**: cumulative cost (USD)

The stats can be toggled with `C-c C-f`, or controlled via the
`dsh-emacs-modeline-enabled` customization option. The layout and faces are
documented in [UI Styling](ui-styling.md).

## How ctx% is computed

The dsh server computes context pressure itself and pushes it to every client
as `session/control` `projection` frames (`key: "contextPressure"` → projected
tokens, pressure tokens and context window). dsh-emacs feeds this snapshot into
the mode-line: the projected tokens are used when present (`projectedTokens ??
pressureTokens`), and the window comes from the same server projection. No local
model→window map is maintained and no full session refresh is needed — the
segment updates as the server's projection frames arrive. Without a server
snapshot the ctx segment is simply hidden; a model change or session open pulls
the projection immediately.

## Mode Line (session buffer status bar)

dsh-emacs does **not replace** your mode line; instead it adds small
segments to your existing (default or custom) `mode-line-format`. While **dsh
is running** (after sending a prompt, before `turn/end` is received), the
whale tail swings. Native mode lines place it beside the DSH mode name;
Doom animates its existing right-side major-mode tail, followed by the stats,
while the larger logo stays before `buffer-info`. No extra progress bar or
second tail is added. The modified flag, line/column position, primary/secondary modes,
misc-info, and all other existing content are preserved:

```
 U:***  %b   L40  DSH [whale tail] Deep diving · 12s (model max 95.0%)
```

- **Whale-tail animation**: the web animation replaces the old filled progress
  bar. `motion-line` owns one shared timer and independent playback slots
  for all chat buffers. Repeated running snapshots do not reset the loop.
  Playback controls in another buffer keep the pending tick's deadline, so
  repeated starts or cleanup cannot starve a running tail.
- Opening an already-running session seeds the indicator from that session's
  cached host status, including after restarting Emacs when `turn/start` is
  outside the retained history window. The elapsed clock starts at local open.
  Cached status seeds only a fresh transcript; reconnecting an existing chat
  preserves its observed state so a delayed cache cannot undo `turn/end`.
- Ending the last active turn or compaction, or disconnecting, stops only
  that chat's slot. Buffer death and major-mode changes also release it.
  No scheduler remains once all slots stop. Hidden buffers skip intermediate
  rendering and catch up when visible.
- The native running indicator is hidden when idle. Doom returns to its static
  major-mode tail; other status labels and stats retain their normal layout.
- The splicing is done with `(:eval …)` and is recomputed live on
  `force-mode-line-update`.
- **Buffer name**: session buffers are named `dsh: <list title>` (matching the
  title of the row in the `*dsh-sessions*` list, with `dsh: ` prepended), which is
  what `%b` in the mode line shows; a `%` in the title is replaced with the
  full-width `％` (mode-line `%`-expansion would swallow characters), sessions
  with the same title automatically get a `<N>` suffix, and the buffer is
  renamed automatically with the list refresh after a title drifts or is
  renamed. Sessions without a title use `dsh: <session-id>`; subagent chats
  use `dsh: <parent title>/<label>`.

The animation lights up when a message is sent or compaction starts and goes
out when both activities finish; it is cleaned up automatically when the
event stream disconnects.
While a text refresh is pending, the animation advances without forcing an
additional redraw; the text refresh also paints the indicator. Quiet visible
turns redraw through the shared animation scheduler. See
[037](../postmortem/037-streaming-display-cpu.md) and
[095](../postmortem/095-running-status.md).

### Step badge

A turn is executed in **steps**, one model call plus the tool executions it
requested (`step/start` … `step/end`).  Steps are turn-internal boundaries,
not conversation, so they never appear in the transcript.  With
`dsh-emacs-modeline-show-step` enabled (**off by default** — the step number
is diagnostic, so the mode line stays quiet unless asked), the running turn's
step shows right after the running whale tail:

```elisp
(setq dsh-emacs-modeline-show-step t)
```

```
 U:***  %b   L40  DSH [whale tail] Deep diving · 12s step 2 · 3s  (deepseek-v4-flash max code 95.0%)
```

- The badge comes from `dsh-emacs-modeline-note-step`, which the renderer
  calls for every `step/start` / `step/end`.  It is hidden whenever the option
  is off or the running animation is hidden: a finished turn's last step is
  not a status.
- The elapsed time (`· 3s`, then `· 1m05s`) is measured in local wall-clock
  time, not from the event timestamps: a reconnect or session reopen replays a
  still-open turn's `step/start` from history, and the wire timestamp would
  then claim hours.  It appears once the step passes one second, advances with
  the animation's redraws (no timer of its own) and freezes at `step/end`.
- The tooltip carries the full `dsh turn N · step N`, which the badgeless
  compact form elides.
- A `step/end` only closes the step it names, so a replayed or out-of-order
  end cannot replace a newer step.

### Execution feedback

Retry status appears beside the running activity:

| Label | Meaning |
|---|---|
| `Retry 1/3` | Waiting before the first retry, with a limit of three retries |
| `Retrying 1/3` | That retry request has started |
| `Retry 7` | Waiting to retry under a policy with no fixed retry limit |

During context compaction, teal `Compacting · 12s` replaces `Deep diving` in
the existing whale-tail slot, with the same gentle text sweep. Its clock
starts when the buffer observes that compaction and does not reset on
repeated snapshots of the same operation. The underlying turn clock keeps
running; when compaction finishes, `Deep diving` resumes with that elapsed
turn time. Standalone compaction between turns starts the same slot without
claiming a running turn. Without Motion Line, the caption is static
`Compacting`, with no clock or animation timer.

Hover or click the label, or run `M-x dsh-emacs-describe-status`, to see
the provider, retry count, scheduled wait and last failure reason/code when
available. The scheduled wait is the server's delay, not a local countdown.
The details buffer is a snapshot taken when opened. If retry and compaction
overlap, the retry label remains beside `Compacting`; Plan state stays
independent too.

These labels come from `llm/retry`, `llm/retry-started`, `compaction/start`
and `compaction/end`. Matching completion/cancellation boundaries clear them;
disconnect clears them immediately. Reconnection rebuilds state from the
follow snapshot's retained event window, independently of transcript dedup.
If that window no longer includes the operation's start, no label is shown:
the client has no current evidence of it. Loading older history never changes
the current execution status. Compaction shares the existing Motion Line slot
and scheduler; it adds no polling or separate animation timer.

Retry transitions and compaction start/end do not add transcript rows.
An automatic `compaction/summary` event adds a folded **Automatic compaction**
row. `RET` or a click expands the generated summary. Its header counts the
covered items and shows an approximate token count for the old context, for
example `3 history items · ~42k tokens`. Neither value measures saved tokens
or the context that remains. The original conversation stays visible, and raw
model output and the checkpoint body stay hidden. The neutral title records a
summary being generated, since applying the checkpoint can still fail
afterward. Such a failure leaves a separate
`Context compaction failed` card. Manual `/compact` summary events are hidden;
the existing command result card keeps its counts and result or failure text.
If the retained history window lacks the summary, no summary row is shown
and no extra fetch is made. See [104](../postmortem/104-auto-compaction-feedback.md).

### Plan mode

The mode line shows the session's collaboration mode even when no turn is
running:

| Label | Current state | Requested change |
|---|---|---|
| `Plan` | Active | None |
| `Plan → on` | Inactive | Enter Plan mode |
| `Plan → off` | Active | Leave Plan mode |
| Hidden | Inactive or unavailable | None |

Use `/plan` to enter and `/plan off` to leave. Hover, click or run
`M-x dsh-emacs-describe-status` to inspect the current and pending state.
Pending means the host has not confirmed the selected mode; it is not a
request for user approval. During a turn the switch applies at the next
accepted step; between turns the host can apply it immediately.

The `plan` projection is authoritative. Finishing a turn or loading older
history keeps the current mode. A disconnected chat retains its last known
mode; opening a new core connection clears the old generation's state and
reseeds it. Follow snapshots and control baselines merge by sequence, so an
older snapshot cannot undo a newer selection, including a pending switch.
An absent `plan` key in a current baseline removes the badge and means the
capability is unavailable.

Plan mode supplies planning guidance to the model. Sandbox permissions and
approval policy remain independent. Todo cards continue to show task progress;
their presence does not imply that Plan mode is active.

### Queue and background jobs

Pending input stays in the Composer Next Message preview above the input.
Use `C-c C-q` (`dsh-emacs-list-queue`) for queued/steering counts and the full
queue manager. Neither native nor Doom mode lines show a queue segment;
counts are not passively visible when the input area is off screen. See
[queue ownership](architecture.md#pending-input-queue-inbox-projection-on-sessioncontrol)
and [decision record 114](../postmortem/114-remove-queue-modeline.md).

Background jobs use their transcript tool rows for status. `C-c C-j`
(`dsh-emacs-list-jobs`) opens the job manager; they have no mode-line segment.

### Why the branch segment is cached

The branch segment has a 10-second TTL cache
(`dsh-emacs-modeline-branch-refresh-interval`): the running whale animation
can trigger a mode-line recomputation about every 50ms, and without caching each
tick would fork a `git rev-parse` subprocess (~30ms+), which would freeze Emacs;
the nil result for non-git directories is cached too, so it never respawns.

## Subagents

The child count uses a 1px SVG with a brain above three downward branches,
inheriting
`dsh-emacs-modeline-face` like the existing status text. Without SVG support it
uses `nerd-icons`' `nf-md-source_branch` when available, then `Sub`.
The total uses bold digits and a half-character gap after the icon, like
Flycheck's mode-line counts, while keeping the muted status-text color.
`Sub 3` means three direct children in the text fallback. Only the total is
shown; the tooltip includes the running count. Mouse-1 opens
`dsh-emacs-list-subagents` in the
minibuffer.
Child chats show their direct parent, label and mode. A child that has
descendants can also have its own child-count indicator.
The completion annotations' cumulative token projection includes uncached
input, output, cache read and cache write; it is independent of this mode line's message-based
usage accumulator and does not estimate cost.

## Testing the optional animation integration

`scripts/verify.sh` works without Motion Line: the suite checks loading and
running-state cleanup in a fresh Emacs process with no animation library, and
the animation playback tests report skips. When an engine is available the
gate runs the suite against it as well, preferring the sibling
`../motion-line` checkout — engine development lives there — over an installed
package; `DSH_MOTION_LINE_DIR` overrides both. To run one configuration by
hand:

```sh
emacs -Q --batch -L /path/to/motion-line -l test/dsh-test.el
```

Those tests need an engine that exposes the deterministic seams
`motion-line-current-time-function` and `motion-line-visible-p-function`
(that repository's postmortem/002). An older install fails loudly instead of
silently skipping, so a stale package cannot leave the animated path
unverified.
