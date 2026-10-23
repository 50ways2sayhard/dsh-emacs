# Sending editor context into a chat

The chat input is where prompts are written, so code that a prompt talks
about has to reach that input. These commands gather the active region, the
file at point, dired's marked files, the line under point, or a screenshot
and leave it in the chat's input area, where the draft is still editable and
`C-c C-c` decides when to send. The command family mirrors agent-shell's
`agent-shell-send-*` commands, adapted to how dsh consumes context.

| Command | Context it sends |
|---|---|
| `M-x dsh-emacs-send-dwim` | In dired: marked files; with an active region: the region; in a chat buffer: reads a file name; in a file-visiting buffer: the file; elsewhere: the line at point |
| `M-x dsh-emacs-send-region` | The active region |
| `M-x dsh-emacs-send-file` | The file at point (dired: marked files; other buffers: reads a name) |
| `M-x dsh-emacs-send-other-file` | Always reads a file name |
| `M-x dsh-emacs-send-screenshot` | A screenshot, captured by `dsh-emacs-send-screenshot-command` |
| `M-x dsh-emacs-send-region-to` / `-file-to` | Same, but first read the target chat |
| `M-x dsh-emacs-send-dwim` with a prefix argument | Same, but first read the target chat |

With a prefix argument, `dsh-emacs-send-file` reads a file name instead of
using the buffer's file. There are no default keybindings: the attachment
keys (`C-c C-a`, `C-c C-v`, `C-c C-d`) stage uploads and stay as they are.

## What lands in the input

**Files travel as `@` mentions, not as uploaded bytes.** The chat receives
`@relative/path` text; the host resolves the path against the session's
working directory and the model reads the file when it needs the contents.
Paths outside the chat's workspace stay absolute, and directories keep their
trailing slash. When several files are sent at once (dired), their mentions
are joined with spaces. See [@ references](reference.md) for the mention
grammar.

**Images are the exception.** A filesystem read cannot show the model pixels,
so an image file that matches `dsh-emacs-attach-media-types` is staged as an
attachment instead (the same list `C-c C-a` feeds), and `C-c C-c` sends it
with the drafted caption. Everything else about staging — the `✕` row, `C-c
C-d`, upload at submission — is
[attachment staging](customization.md#attachment-staging).

**Regions and lines travel as text**, because a dsh `@` mention has no
line-range syntax. The context is an `@file (lines A-B):` header followed by
a fenced code block whose language comes from the major mode; a buffer
without a file uses `Buffer NAME (lines A-B):` instead. The text is appended
to an existing draft separated by a blank line, so a send command never
discards a half-written prompt.

## Choosing the chat

The target is the chat buffer you are in; otherwise the open chat whose
working directory contains the current buffer's; otherwise the only open
chat; otherwise a completion prompt over the open chats. The `-to` variants
and a prefix argument always prompt. The context is inserted and the target
buffer is shown, so the next thing you see is the chat with its new draft.

## Screenshots

`dsh-emacs-send-screenshot-command` is the command list that captures a
screenshot; each argument containing `%s` is expanded to a temporary PNG
path. The default is `("screencapture" "-i" "-x" "%s")` on macOS, whose
interactive selection UI may be cancelled (reported as a user error, nothing
staged). On other systems the option is nil and the command reports that
capture is unavailable; set it to an equivalent command to enable the
feature. The temporary file is removed after the image is read.
