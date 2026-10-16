# 109 — Read history independently in each chat window

_Loading interaction, question navigation and the Imenu keybinding are
superseded by [110](110-load-complete-rounds.md); independent per-window
reading, trim deferral and the user-message Imenu index remain in use._

## Background

The UI marker change in `98ac701` fixed edits above readers, but older pages
still wrapped rendering in `save-window-excursion` (records 044 and 107).
A real GUI replay of stored history found 23 fragment-level recenters during
one page. Removing the wrapper moved an interior reader by five lines; with
or without it, a window starting exactly at the insertion point displayed
new text instead of retaining its old start. The failing layer was UI
following: fragments made a separate geometric decision from stream output.
The renderer also trimmed the page it had just inserted when over the cap.

## Decision

Keep one transcript and let each window read independently. The history
module owns page loading and question navigation; it saves advancing start
and point markers plus scroll offsets for every view during insertion.
There is no saved window configuration. Cards ask the renderer for the same
following-window set as streaming; historical pages supply an empty set.
A nonselected window must satisfy the same point-at-input test as a selected
one. Size-based trimming waits for readers and skips older-page insertion.

Reuse the existing user-message text property and stock Imenu for a question
directory. Marker targets survive concurrent insertion, and auto-rescan
refreshes the directory. Add previous/next question and return-to-draft
commands. Loading pages remains explicit, with the existing message budget.

## Why

Stable reading fixes the immediate conflict between history and live output.
Separate history buffers would duplicate rendering and require a snapshot
synchronization policy. Persistent per-window reading flags would add state
that can disagree with ordinary Emacs movement. Sharing the current-point
policy removes the conflicting decisions without adding that state.

Moving the page command and index out of the entry point gives browsing one
owner as navigation is added. It does not add a parallel event model, an
index cache, or helper wrappers around the renderer. A soft cap intentionally
trades temporary memory growth for preserving text the user is reading.

## Consequence

`M-x imenu` opens the loaded-question directory; `C-c >` returns only this
window to the draft and following output. `C-c C-o` retains the displayed
text, including at the insertion boundary. The `C-c [` / `C-c ]` question
navigation and the `C-c C-i` binding added here were dropped again by
[110](110-load-complete-rounds.md), which also replaced the single-page load
this record describes.
Unit regressions reproduced the three viewport/trimming failures and the
missing first Imenu entry before their fixes. GUI tests exercise the actual
keys, a page containing a tool card, two readers, a trimmed header, and a
live card growing while another window keeps reading.

## Known limitations

Search remains within loaded text. Cross-page search and a separate history
buffer are deferred by agreement. Pages still use message boundaries;
turn-aligned paging can be added separately without changing navigation.
Navigation visits authored questions, not every autonomous turn.

The existing character-based trim can still cut an old turn and does not
rebase the server pagination frontier. This pre-existing limitation is not
solved by protecting active readers; set `dsh-emacs-max-buffer-size` to nil
when all loaded text must remain available. A long reading session can
exceed the cap until later live events find no displayed reader.
