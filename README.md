# dsh-emacs — an Emacs client for DeepSeek Harness

**dsh-emacs** brings [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
(`dsh`) into Emacs: streaming replies, tool calls, thinking blocks, slash
commands, file/session references, and model selection. It uses Emacs
built-ins (Emacs 27.1+) with no third-party dependencies.

![Chat buffer with streaming replies and tool calls](assets/chat.png)

> **0.5.x** targets the **dsh 0.1.7** wire protocol (servers **0.1.5 or newer**:
> the queue surfaces read the `inbox` session projection, which 0.1.5, 0.1.6 and
> 0.1.7 all publish).

## Quick start

You need **Emacs 27.1+** and a provider/model configured in dsh to send
messages. dsh-emacs can install and start the dsh server for you; provider
credentials and model configuration remain in dsh. For an existing local or
remote server, set its address as described in [Server setup](#server-setup)
before connecting.

1. Clone the repository:

   ```sh
   git clone https://github.com/vritser/dsh-emacs.git ~/dsh-emacs
   ```

2. Add this to your Emacs configuration and evaluate it, or restart Emacs:

   ```emacs-lisp
   (add-to-list 'load-path (expand-file-name "~/dsh-emacs"))
   (require 'dsh-emacs)
   ```

3. Run `M-x dsh-emacs` to open the session list. If no local server is
   running, dsh-emacs starts one, offering to install the CLI if it is missing.
   On a fresh dsh setup, use `M-x dsh-emacs-open-web` to configure your
   provider and model before sending a message.
4. Press `c` in the session list to create a session. Use `C-c C-m` in the
   chat buffer to choose a model if needed.
5. Type after the `❯` prompt and press `C-c C-c` to send your first message.

For an optional `use-package` setup, see
[Example configuration](docs/customization.md#example-configuration).

## Using it

Chat buffers show the DeepSeek Harness whale in the mode line when SVG is
supported: blue on dark themes, black on light themes, with `DSH` as the
terminal fallback. Colors follow theme changes. The icon keeps the
standard Emacs major-mode menu. See [Mode-line status](docs/modeline.md).
With [Motion Line](https://github.com/vritser/motion-line) installed, a running
turn shows the same swinging whale tail as dsh web (18×18 display size,
60 frames, three-second loop), followed by `Deep diving · 12s` with a gentle text sweep and elapsed
time. Terminals show cycling `DSH...` text with the caption and clock.
Opening an already-running session restores this indicator after an Emacs
restart, even when its turn started before the loaded history window.

Motion Line is optional and installed separately. Without it, the mode line
shows a static `Deep diving` or `Compacting` caption for the active phase
and clears it when both activities finish or the session disconnects. This
fallback uses no animation timer or elapsed clock. See
[Mode-line status](docs/modeline.md) for setup.

Chat buffers are named `dsh: <title>` (or `dsh: <session-id>` before a title
is available); subagent chats use `dsh: <parent title>/<label>`.

When `nerd-icons-completion` is active, DSH chat buffers use the whale icon in
Consult's buffer-switch minibuffer (`C-x b`).

### Session list

`M-x dsh-emacs` opens your sessions, grouped by workspace. Press `c` to
create a session or `RET` to open one. From a local project file or directory,
the command expands the workspace matching the project root and centers its
header in the selected window when space permits. Near the start of the list,
the view starts at the buffer boundary instead.
It waits for workspace data if needed and does not create a workspace. Your
next command in the list cancels pending automatic navigation, so later data
does not pull you away from manual navigation or folding.
From a chat buffer, it still locates the active session; remote servers and
TRAMP directories keep the usual session navigation.
`TAB` folds a workspace header or
expands a session's subagents beneath it. Only sessions with confirmed children
show an expansion arrow and respond to `TAB`; unknown or empty catalogs remain
unchanged. Child rows show their mode and activity; use `TAB` for nested
children and `RET` to open a child conversation.
Expansion and cursor position survive refreshes. See
[Session and workspace controls](docs/customization.md#session-and-workspace-controls)
for list management and navigation.

![Session list grouped by workspace](assets/sessions.png)

### Subagent conversations

`M-x dsh-emacs-list-subagents` (or mouse-1 on the mode-line child count) opens
minibuffer completion for this conversation's direct children. `RET` opens the
selected chat; `C-u` before the command opens it in another window. `C-g`
cancels and `M-,` returns to the originating chat position through xref.
Inside a child, run the command again to select its children. Your normal
completion frontend and keys apply; no separate browser buffer is created.

The count uses a thin brain-and-circuit SVG, with the brain above three
downward branches, in the existing muted status-text color.
Without SVG support it falls back to Nerd Font `source_branch`, then `Sub`.
The total is bold, with a thin gap after the icon (text fallback: `Sub 3`);
hover for the running count.
Candidates show mode, activity and available duration/token metrics.
`M-x dsh-emacs-subagent-refresh`
refreshes the current conversation's catalog and parent availability.

Continuable children accept text with `C-c C-c` and stop with `C-c C-b`;
`C-u C-c C-c` steers. Input closes while the parent is unavailable or the host
connection is lost. One-shot children are read-only and cannot be interrupted
through this surface. `C-c C-o` pages older child history. Queue editing, model
selection, attachments, slash commands and late question answers are unavailable
inside child chats. `M-x dsh-emacs-subagent-stop` chooses a running continuable
child to stop after confirmation; `M-x dsh-emacs-subagent-describe` chooses a
child for detailed inspection. Token totals include cache usage and are session
projections, not billing estimates or the chat mode line's message accumulator.

See [subagent integration](docs/subagents.md) for protocol and test details.

### Inside a chat buffer

| Key | What it does |
|---|---|
| `C-c C-c` | Send input or interrupt; see below |
| `C-c C-b` | Interrupt the running turn |
| `C-c C-q` | Manage the pending queue |
| `C-c C-j` | Manage background jobs (view output / stop) |
| `C-c C-p` | Answer a timed question whose window expired (dsh 0.2.0) |
| `C-c C-g` | Open the goal-action prefix |
| `C-c C-m` | Switch model / reasoning effort |
| `C-c C-e` | Switch the running model's reasoning effort |
| `C-c C-a` | Stage one file for the next message; repeat to add more |
| `C-c C-v` | Paste the clipboard image into the next message |
| `C-c C-d` | Discard staged attachments |
| `s-v` | Paste a clipboard image, else yank text |
| `C-c C-s` / `C-c M-s` | Switch session in this workspace / across all |
| `C-c C-r` | Refresh |
| `C-c C-o` | Load 3 complete earlier rounds; prefix chooses the count; press again to cancel |
| `C-c >` | Return this window to the draft and follow new output |
| `C-c C-w` | Copy (region → code block → message at point → last reply) |
| `C-c C-y` | Fork into a new conversation through the assistant reply at point |
| `C-c C-f` | Toggle mode-line stats |
| `C-c C-!` | Stop the tracked local shell process |
| `M-p` / `M-n` | Previous / next input |
| `C-/` / `C-_` / `C-x u` | Undo input editing; redo with `C-g C-/`, or `undo-redo` on Emacs 28+ (the transcript is never undone) |
| `TAB` | Complete a slash command or skill |

**Reading history:** `C-c C-o` loads the previous 3 complete rounds.
Use `C-u 1 C-c C-o` for one round or `C-u 5 C-c C-o` for five.
A partly loaded oldest round is completed first and counts toward the total.
Long rounds are fetched across as many bounded requests as needed. When done,
the initiating window shows the newly loaded range, with a completion message
such as “Loaded rounds 7–9 (3 rounds)”. If you moved point while
waiting, your new position is kept; other windows always keep their place.
Press `C-c C-o` again while loading to cancel. `M-x imenu` opens the normal
Imenu question directory; `C-c >` returns to your draft and follows output.
These controls work while a reply is running. History is not trimmed while a
displayed window is scrolled away from the bottom. See
[history controls](docs/customization.md#reading-history).

Background-job status appears in the tool rows. Use `C-c C-j` to inspect
retained output or stop a job; the mode line has no separate job count.

**Branching a conversation:** place point in a committed assistant reply
(including its code blocks) and press `C-c C-y`, or run
`M-x dsh-emacs-fork-message-at-point`. The new conversation includes that
reply and its preceding history, excluding later events, and opens
automatically. Replies still streaming and subagent conversations cannot
be forked this way. In the session list, `f` forks through the latest
completed turn instead. See [fork controls](docs/customization.md#forking-conversations).

Between rendered human messages, only the latest completed turn with a
nonempty reply keeps a small row after all its content, including
Deliverables, tool cards and error messages:
`Copy · Fork · Tokens 12.3k · Time 8.2s`. A completed background follow-up
replaces the earlier row, not the earlier reply text; unfinished or empty
turns leave it in place. Goal notices and hidden subagent traffic do not start
a new group. Click an action or press `RET` on it (`TAB` moves between buttons).
Copy and Fork target that turn's last text reply; Copy preserves its original
Markdown. Tokens and Time describe only that turn, not the whole group.
Tokens include reported input, output and cache usage; hover for the breakdown.
Time includes tools and waits. Incomplete history shows a token lower bound
(`≥`), and unavailable values show `—`.

Choose the items and their order, or hide the row entirely:

```emacs-lisp
(setq dsh-emacs-reply-footer-items '(copy fork usage duration)) ; default
;; (setq dsh-emacs-reply-footer-items '(copy usage duration))  ; omit Fork
;; (setq dsh-emacs-reply-footer-items nil)                     ; hide the row
```

Refresh existing chats after changing the option. See
[reply footer settings](docs/customization.md#reply-footer) for statistics scope.

**Sending during a running turn:** by default, `C-c C-c` queues a non-empty
message for the next turn. `C-u C-c C-c` steers the running turn instead;
`C-c C-c` with blank input and no staged attachments interrupts it. Configure
this with `dsh-emacs-busy-enter-behavior`. The `C-c C-q` queue menu acts on the
highlighted item; `x` deletes all pending items. Next Message offers inline
actions after the server confirms the queued item. Send-now can steer an
attachment-bearing item into a running turn, but refuses it while idle and
leaves it queued; idle resubmission supports text-only items.

Type **`@`** to choose file, directory or session references: `@src/` drills
into a directory and `@session-title` mentions another session. Discovery runs
in the background; matching ignores case and searches paths or session metadata,
not just the displayed label. Corfu updates as results arrive; with other
frontends, press `TAB` again if the first request is still loading. See
[@ references](docs/reference.md).

Type **`/`**, then press **`TAB`** to complete a slash command. Automatic
popups depend on your completion front-end and its settings: corfu/company
can provide them with auto completion enabled; stock completion,
vertico and icomplete require `TAB`. The same list carries the session's
skills (host instruction bundles), with user-only ones marked. The token
completes wherever the host accepts a gesture — at the start of the message
or after a space — so `please /rev` + `TAB` becomes `please /review `; a
name no command or skill matches is left to path/word completion. See
[Slash commands](docs/slash-commands.md#three-ways-to-run-a-command) and
[Skills](docs/skills.md).

**`TAB`** completes a **local file path** once the token carries a separator:
`docs/rp`, `./src/`, `~/…` and `/abs/…` complete through the stock file-name
completer against the chat buffer's working directory — the session workspace
— with the same directory drill-down as `find-file`, the path suffix after
the cursor preserved, and the active completion styles (abbreviated
directories work with `partial-completion`). A `/name` at the start of the
input is reserved for slash commands even when their catalog is empty; in the
middle of a message a `/name` only goes to command completion when a command
or skill actually matches it, so `see /usr` still completes as a path.
Completion reads the machine Emacs runs on, like `!` shell lines — with a dsh
server on another host, use an `@` reference instead. A path with spaces is
not handled in plain text (the token ends at the space); quote it as an `@`
reference.

**`TAB`** also completes an ordinary word from what is already in the buffer:
the draft above point and, within `dsh-emacs-word-completion-limit`
characters, the transcript above it — so a term from an earlier message or
tool result completes instead of being retyped. Words are runs of letters,
digits, `_` and `-`, so identifier-like terms such as `dsh-emacs-mode`
complete whole. Candidates appear nearest-first, and completion inside a
word includes the existing suffix. Slash commands and `@` references keep
their own completion even when their catalogs are empty.

The composer shows the current goal and the next pending message above `❯`.
Hover over the preview for its full text, or use `C-c C-q` to inspect queue
counts and manage pending messages. The queue has no mode-line indicator.
Goal shortcuts and inline controls are described in
[Goal actions](docs/customization.md#goal-actions).

The mode line shows `Retry 1/3` while waiting to retry, `Retrying 1/3` once
the request starts. During context compaction, the whale's caption changes
to teal `Compacting · 12s`, with its own elapsed clock and gentle sweep when
Motion Line is installed. It also appears between turns; without Motion
Line it shows static `Compacting` text. When compaction finishes during a
turn, `Deep diving` returns with the turn's original clock. Hover, click, or
run `M-x dsh-emacs-describe-status` for details. See
[Execution feedback](docs/modeline.md#execution-feedback).

Automatic compaction leaves a folded **Automatic compaction** row in the
transcript, styled like a compact tool row with the existing terminal icon
and no extra blank padding. `RET` or a click expands the Markdown summary;
the muted header counts describe covered history items and approximate tokens
in the old context, not tokens saved. The original conversation stays visible.
The neutral title does not claim checkpoint success: a later compaction failure
gets its own error card; manual `/compact` keeps its command result card.

Plan mode shows `Plan` while active, or `Plan → on` / `Plan → off` while a
switch is pending. Use `/plan` to enter and `/plan off` to leave; the badge
persists across turns. See [Plan mode](docs/modeline.md#plan-mode).
Submitted plans open as readable Markdown in a separate buffer, with
**Approve and execute** (`C-c C-c`) and **Request changes** (`C-c C-k`).
Requesting changes returns to the chat input for feedback. `q` only closes
the document window; reopen a pending review with `M-x dsh-emacs-plan-review`,
or open a previous plan from its titled transcript card. See
[Plan review](docs/slash-commands.md#plan-review).

Expanded file-edit cards show unchanged lines once as context, with red/green
rows and totals for the changes. See
[Tool cards](docs/ui-styling.md#tool-calls-dsh-web-style) for the display
rules, including the limit for very large replacements.

### Answering questions

Agent `ask` prompts are answered in one minibuffer read. The question text is
the prompt, the options are the completion candidates (each one carries its
description as an annotation), and the question detail shows in the echo area.

- Single choice: pick a candidate, `RET` accepts it. Empty input skips the
  question.
- Multiple choice: type the options comma-separated — `2,3` or `alpha,beta` —
  and `RET` submits them (`completing-read-multiple`, Emacs' standard
  comma-separated input path). An unambiguous prefix works too (`alph`), and
  an ambiguous one is left as your answer text rather than guessed.
- Anything that names no option is taken as your answer text, like at any
  Emacs completion prompt — there is no separate "type an answer" step, and
  a partly-matched answer is never silently trimmed.
- `C-c C-s` skips the question (empty input does the same); `C-g` abandons
  the whole group.

Nothing is toggled in place and the reader never reopens: one read per
question, so the menu cannot flicker or reorder.

```elisp
(setq dsh-emacs-question-help-display 'echo-area) ; default; nil hides the detail
```
Try `M-x dsh-emacs-question-preview` locally, without contacting a server.
See [Question prompts](docs/customization.md#ask-question-prompts) for details.

### Approval reasons

Approval prompts use the host's localized reason when available (dsh 0.2.0),
following the Emacs message locale. To select Chinese explicitly:

```elisp
(setq dsh-emacs-approval-language "zh") ; nil follows the Emacs locale
```

Missing translations fall back to English, then the original reason. See
[Approval prompts](docs/customization.md#approval-prompts) for the lookup order.

### Workspaces

Workspaces group sessions by project/directory.

New sessions use the current workspace when created from a workspace header,
its empty New Session row, or an existing chat. Without that context, a
**local server** can use the Emacs project of the current buffer's directory,
creating its workspace on first use. This detection is controlled by
`dsh-emacs-new-session-auto-project` and does not run for remote servers.
Otherwise the new session uses the current buffer's directory.

New session commands immediately open an editable **DSH Draft** buffer while
server readiness, workspace creation and session creation run asynchronously.
When ready, the same buffer becomes a chat and keeps your text and cursor.
Sending is unavailable while creating. On failure, the header shows the error;
`C-c C-c` retries with the draft intact and does not send it. Closing a draft
prevents it from reopening, but an already accepted session can still appear
in the session list.

### Local shell commands

Enter `!git status` and press `C-c C-c` to run a command locally in the
session's workspace directory. Output appears in the transcript, including
while a model turn is running. `C-c C-!` stops the tracked shell process.

Shell output is not sent to the model or saved in server history; refreshing
the transcript removes it. With attachments, a leading `!` is caption text
sent to the model. See [Shell commands](docs/shell-commands.md) for multiline
scripts, shell selection and process handling.

### Skills

dsh skills are host-side instruction bundles (`SKILL.md` plus resources) for a
session's working directory and preset. dsh-emacs lists them in the `/`
completion (user-only ones marked) and in `M-x dsh-emacs-command`, the same
menu that runs slash commands: picking a skill inserts `/name ` at the cursor,
or with `C-u`, opens the picked skill's `SKILL.md`. The host expands a `/name`
gesture found in your prompt, so a skill is invoked like ordinary text
(`/review check the parser`). See [Skills](docs/skills.md).

### Attachments

An **image** whose type is in `dsh-emacs-attach-media-types` rides the prompt
inline and reaches the model as an image. Any **other file** is uploaded to
the host when the prompt is submitted and reaches the model as a file
attachment; the transcript shows it as a display-only `[file: name · size]`
line. `dsh-emacs-attach-max-file-size` caps an uploaded file (32 MiB by
default, `nil` lifts the cap), and an inline image is not governed by it.

`C-c C-a` (`dsh-emacs-attach-file`) reads one existing file with Emacs's
standard file-name prompt and appends it to the staged-attachments row above
the input. Repeat the command to add more files. It neither contacts the
server nor asks for a caption. Drag-and-drop keeps its yes/no confirmation
and appends all valid dropped files in their existing order to the same
list; neither action sends immediately. There is no separate multi-select
picker.

Type your message in the chat input, then press `C-c C-c` to send it with the
whole staged set. Blank input sends the staged file names as the message text.
Files upload when the send starts. Each file's `✕` on the row drops just that
file; `C-c C-d` discards the whole staged set.

`C-c C-v` pastes the system clipboard's image into the same staged list.
`s-v` does the same as `C-c C-v` whenever the clipboard holds an image, and
falls back to ordinary text yank otherwise; `C-y` always stays a plain text
yank, so a clipboard carrying both an image and text can still paste the text.
Where the pasteboard exposes TIFF rather than PNG (macOS), the image is
converted with the system `sips` tool before upload, provided PNG is in
`dsh-emacs-attach-media-types`. A rejected send restores its caption and
attachments only while both the input and staged attachments are empty; a
failed upload likewise restores them and sends nothing. Emacs 29+ users can
also run `M-x yank-media`.

### Models & presets

Use `M-x dsh-emacs-add-provider` to select a pi-ai catalog provider or enter
a custom provider name. Minibuffer prompts collect the endpoint, protocol
and model IDs as needed, then the API key through a password reader. Settings
and credentials are saved on the connected dsh server; `C-c C-m` then selects
a model. Selecting an existing provider updates its endpoint/key while
preserving its model definitions and other settings. See
[Adding providers](docs/customization.md#adding-providers).

Other provider families and account sign-in use `M-x dsh-emacs-open-web`.
For advanced configuration and agent presets, edit dsh's configuration files.
`M-x dsh-emacs-edit-config` asks for an existing configuration file and opens
it for ordinary editing and `C-x C-s` saving. It remembers the choice per
server URL for this Emacs session; use `C-u M-x dsh-emacs-edit-config` to
choose again. Remote files use an explicit TRAMP path. See
[Editing dsh configuration](docs/customization.md#editing-dsh-configuration).
`C-c C-e` selects the running model's reasoning effort directly; `C-c C-m`
also offers it as the second step of a model switch.

`dsh-emacs-default-preset` selects the preset for new sessions; nil uses the
host default. `dsh-emacs-default-model` is a display fallback for the mode
line and does not select the model used by a session. See
[Model picker](docs/model-picker.md) for details.

## Server setup

By default dsh-emacs manages a local server. To use one you run yourself, set
`dsh-emacs-base-url` to its address. Remote addresses, including HTTPS and
URLs with `user:pass@` Basic auth, never trigger a local server start. Set
`dsh-emacs-server-auto-start` to nil to disable automatic startup locally.

For a server dsh-emacs starts, launch-token authentication is automatic.
For a server you started yourself, provide the launch token from the URL it
prints (`dsh web: …/?token=…`). You can set `dsh-emacs-server-auth-token` to
the token, or paste the whole URL into `dsh-emacs-base-url`.
If a reverse proxy also requires Basic authentication, include its separate
credentials as `http://user:pass@host:port`; the dsh launch token is still
required. RPC authentication failures report HTTP 401 instead of asking for
a username and password, and clear the rejected cookie before the next attempt.

When prompted for an external server's token, a successful answer is saved
for reuse. After a server restart, the previous token may be stale and need
replacing. See [Server options](docs/customization.md#server-options).

## Streaming and appearance

Replies and thinking appear as they arrive. Large Markdown regions finish
styling while Emacs is idle; see
[Markdown responsiveness](docs/customization.md#markdown-responsiveness)
for tuning options.

Use `M-x customize-face` or `custom-set-faces` to change the appearance.
[UI styling](docs/ui-styling.md) lists the active faces and explains rendering;
the [streaming performance audit](docs/streaming-performance.md) records
measurements and remaining limits.

The composer's Goal and Next Message rows use the buffer background, with their
action icons placed directly after the text; `C-c C-g ?` opens the full goal
details.

## Documentation

- [Customization](docs/customization.md) — configuration examples and options
- [@ references](docs/reference.md) — file, directory and session mentions
- [Slash commands](docs/slash-commands.md) — catalog, completion and execution
- [Skills](docs/skills.md) — host skill catalog and `/name` gestures
- [Shell commands](docs/shell-commands.md) — local `!command` execution
- [Model picker](docs/model-picker.md) — models, providers and reasoning effort
- [Mode line](docs/modeline.md) — running status, context usage and subagents
- [UI styling](docs/ui-styling.md) — faces and Markdown rendering
- [Development & testing](AGENTS.md) — workflow and verification
- [Architecture](docs/architecture.md) — module ownership and event flow
- [RPC protocol](docs/rpc.md) — methods, events and projections
- [Fragment extension API](docs/architecture.md#transcript-fragments-dsh-emacs-uiel) — snapshots and card styling
- [Changelog](CHANGELOG.md)

## Contributing

Development workflow and commit conventions are in [AGENTS.md](AGENTS.md).
Keep pull requests focused on one topic; for non-trivial work, open an issue
first to align the scope. Run `scripts/verify.sh` before pushing. It checks
syntax, checker and test-runner self-tests, byte compilation, the full unit
suite, silent loading, diff whitespace, and generated-file cleanup.

After saving local source changes, run `M-x dsh-emacs-reload` to load all
package modules from source and refresh Composer, session-list and mode-line
presentation. Chats, drafts, attachments, settings, connections and timers stay
in place; the command does not restart dsh or send a prompt. It refuses while
a minibuffer/question/approval interaction, session creation or history load
is active. There is no default keybinding.

If this Emacs loaded an older checkout without the command, first use
`M-x load-file` on your checkout's
[dsh-emacs-reload.el](dsh-emacs-reload.el), then run `M-x dsh-emacs-reload`.
Updating files on disk alone does not update a running Emacs. Reload replaces
ad-hoc edits to package keymaps; it does not recreate existing transcript text,
in-flight callbacks or major-mode initialization. Removed definitions and
changed struct layouts still require a restart. See
[Source reload](docs/architecture.md#source-reload) for preflight checks,
customization behavior and partial-failure limits.

Optional [GUI display tests](docs/architecture.md#gui-display-regression-tests)
check actual visual wrapping in a graphical Emacs without a dsh server.

Real-server tests are separate. The batch runner reuses the token saved by
Emacs Customize for the matching server without loading your init; set
`DSH_E2E_CUSTOM_FILE` for a nonstandard Customize path. See
[E2E testing](docs/architecture.md#real-server-e2e-testing) for authentication
precedence, the batch smoke suite and timed-question tests in a running Emacs.

## Acknowledgments

The UI mirrors [dsh web](https://github.com/deepseek-ai/deepseek-harness),
including its tool icons, session list and context meter. Markdown rendering
and folding build on [agent-shell](https://github.com/xenodium/agent-shell);
mode-line stats and compact token formatting follow
[pi-mono](https://github.com/badlogic/pi-mono).

## License

[GPL-3.0-or-later](LICENSE) — GNU General Public License v3 or later.
