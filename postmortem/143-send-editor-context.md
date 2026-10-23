# 143 — Send editor context with an explicit command family

## Background

agent-shell ships a family of `agent-shell-send-*` commands that put editor
state into the agent's prompt: region with file/line context, the file at
point, dired's marked files, a screenshot. The user asked for the same
gesture set in dsh-emacs ([agent-shell.el at 80887a9](https://raw.githubusercontent.com/xenodium/agent-shell/80887a9f8e51c30536327a532936ecf67a2bc869/agent-shell.el)).

dsh-emacs had no such surface. `C-c C-a` (`dsh-emacs-attach-file`) and
`C-c C-v` (`dsh-emacs-attach-clipboard-image`) stage *uploads*; nothing
turned a buffer's region, file or line into prompt content. A user had to
copy the text by hand or type an `@path` mention without the line range the
model would need, and a chat opened from a code buffer had no way to say
"this is what point is looking at".

The reference implementation's mechanics do not transplant directly:

- dsh's `@path` mention is path-only. Selecting one never reads the file;
  the host injects the workspace-resolved path and the model calls a
  filesystem tool when it needs contents. There is no line-range grammar in
  a mention, so a region must travel as text, not as `@path:10-20`.
- An image cannot be inspected through that filesystem read either, so an
  `@screenshot.png` mention would name a file the model cannot see; images
  have to use the existing attachment path.
- agent-shell's `send-*` commands assume shell-maker's busy/prompt-queue
  machinery. dsh chats have one editable input area whose submit is
  `C-c C-c`; context should simply arrive there like typed text.

## Decision

Add `dsh-emacs-send.el`, one module owning the transition from editor state
to a chat's input area, with no submission path of its own: files become
`@path` mentions, regions and lines become an `@file (lines A-B):` header
plus a fenced code block, images and screenshots are staged as attachments,
and every command appends to the draft and pops to the target chat. Public
commands: `dsh-emacs-send-dwim`, `dsh-emacs-send-region`,
`dsh-emacs-send-region-to`, `dsh-emacs-send-file`,
`dsh-emacs-send-file-to`, `dsh-emacs-send-other-file`,
`dsh-emacs-send-screenshot`; `dsh-emacs-send-screenshot-command` is the one
new option.

## Why

- **Reuse the mention grammar instead of inventing context syntax.** Files
  go through `dsh-emacs-reference--format-file-mention`, so quoting for
  whitespace and directory trailing slashes match what the composer already
  produces and what the host parses. The model then decides whether to read
  the file, which keeps prompts small.
- **Inline region text because the mention has no line range.** The header
  names the file and lines; the fence keeps code readable and gives the
  model a language hint. A buffer without a file is labeled by name so a
  scratch buffer still explains itself.
- **Images through staging because the read tool cannot show pixels.** This
  reuses `dsh-emacs--attachable-file` and `dsh-emacs--stage-attachments`,
  including the media-type/size checks and the Composer row, rather than
  adding a second image path. `C-c C-c` remains the single send action.
- **Append, never replace.** A half-written prompt is expensive; a send
  command that overwrote the draft would be a footgun. A blank line makes
  the boundary visible.
- **Resolve the target by workspace, then ask.** In a single-chat setup
  sending is immediate; with several chats, cwd affinity chooses the
  obvious one and the `-to` variants cover the rest. Prompting on every
  invocation would make the common case slower.
- **No default keybindings.** agent-shell itself binds none (its transient
  menu is its entry point). dsh's attachment keys are already taken and a
  guessed `C-c` chord would collide on user maps; the commands are one
  `M-x` away and documented, while `docs/customization.md` shows the
  `define-key` form.

Rejected: extending the `@` grammar with line ranges (host-side feature,
client cannot send it); folding the commands into `dsh-emacs.el` (the entry
point is already the session coordinator, and this surface has no protocol
or session state); reusing `dsh-emacs-attach-file` for regions by writing a
temp file (adds an upload round trip and loses the line-range header).

## Consequence

New commands and one option listed above; no existing keys change. New
module in `docs/architecture.md`, new `docs/editor-context.md`, README
bullet, `docs/customization.md` section, and a 0.7.0 Added entry. Tests in
`test/dsh-test-send.el` cover the region format and draft appending,
relative mentions, cwd-based and prompted targets, the image exception and
screenshot staging through a configured capture command.

`dsh-emacs.el` now requires the module after `dsh-emacs-reference`; the
reload path discovers it automatically. The module declares the entry
point's input-geometry and staging functions instead of requiring
`dsh-emacs.el`, keeping the package load order acyclic.

## Known limitations

- No diagnostics (flymake/flycheck) context source; agent-shell's
  `send-dwim` can include an error at point, dsh-emacs only sends the line.
- Only the active region; there is no "send paragraph" or "send defun"
  gesture.
- Screenshot capture depends on an external command; the macOS default is
  the only one shipped, other platforms must configure it (or the command
  stays unavailable).
- A dired region sends the marked files, matching dired's own semantics,
  rather than the raw text of the selected lines.
