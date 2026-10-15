# 108 — Reduce Markdown allocation instead of adding render layers

## Background

After the streaming work in 029–037 and the render reports in 105, a GUI
measurement on macOS Emacs 31.1.50 showed where the remaining Markdown time
went: rendering a 10 KB reply took 36 ms with the default
`gc-cons-threshold`; 23 ms of that was garbage collection. With collection
deferred the same render took 11 ms, so allocation counted for more than the
parser itself. The change landed on top of the 107 work; commits are cited
below.

The memory profiler pointed to three sources, all in the render layer
(`dsh-emacs-markdown.el`):

- every fenced block created a temporary buffer and ran its major mode once;
  setting up `python-mode` cost about 0.5 ms per block, more than fontifying a
  typical block;
- table rows were built by concatenating propertized strings per cell, per
  line, per row and per table, so every interval was copied (and its property
  list consed) four or five times;
- `--replace-image-file-paths` called `regexp-opt` on
  `image-file-name-extensions` for every `replace-markup` call, including
  every streamed flush.

## Decision

- `--highlight-code` keeps one hidden buffer per major mode
  (` *dsh-emacs-markdown-fontify:MODE*`). It sets up the mode on first use,
  then erases, inserts and runs `font-lock-ensure` for each block. A
  buffer-local marker records a completed setup, so a mode that signals is
  retried on the next block.
- Table rendering inserts borders, padding and cells directly into the
  table's own work buffer, erased once the cells have been parsed into
  strings, and returns one `buffer-string`. `--render-table-data-row` /
  `--render-table-separator-row` became `--insert-table-data-row` /
  `--insert-table-separator-row`; `seq-mapn` gave way to `cl-mapcar` /
  `cl-mapc`.
- The bare image-path regexp is cached together with a *copy* of the
  extension list it was built from, and rebuilt when that list no longer
  compares `equal'. The copy is load-bearing: keying on the variable itself
  would compare the very list object the caller may have edited in place, so
  an edited list would keep serving a regexp built from the old extensions.

## Why

Org (`org-src-font-lock-fontify-block`) and `markdown-mode` use the same
per-mode fontification buffer, so the approach is established. `erase-buffer`
widens, flushes the `syntax-ppss` cache through the change hooks and drops
the previous text properties, so one block cannot affect the next. A
regression test checks that two blocks set up the mode once and that an
unterminated string does not carry over.

Inserting into the work buffer copies each interval once. Rendered output is
`equal-including-properties` to the previous strings; only the order of keys
within some property lists changed.

The regexp cache compares against a stored copy rather than the variable, so
it also notices a list edited in place — `(setcar (cdr ext) "svg")`, `push`,
`nconc`. Comparing identity against the variable would not: it would be
comparing the list with itself. The regression test warms the cache, applies
`setcar`, and asserts the rebuilt regexp knows the new extension and has
forgotten the replaced one; it fails against an identity-keyed cache.

Rejected: caching rendered blocks or tables by source text. That would need
invalidation for window width, fonts and faces, which 035 deliberately keeps
render-scoped. Also rejected: a larger `gc-cons-threshold` around rendering,
which only moves the same collection somewhere else.

## Consequence

Same-machine measurements, compiled code, before → after:

| Workload | Before | After |
|---|---:|---:|
| Batch, 40-section reply (42 KB), median of 5 | 39.8 ms | 27.0 ms |
| Batch, one `python` block | 0.71 ms | 0.20 ms |
| Batch, 3 KB reply streamed in 131 flushes | 11–12.7 ms | 6.1–6.4 ms |
| Batch, 30-row table: conses / intervals per render | 30,609 / 4,111 | 22,678 / 3,126 |
| GUI, 10 KB reply: time, GCs per render | 35–36 ms, 2.0 | 27–28 ms, 1.65 |
| GUI, 30-row table | 23–25 ms | 19–21 ms |
| GUI, 3 KB streamed reply: time, GCs | 47–59 ms, 3.8 | 28–32 ms, 1.8 |

Each section of the reply fixture has a heading, a paragraph with mixed
English, Chinese, bold, inline code and links, a nested list, a blockquote,
a four-line `python` block, a five-row table and a divider. GUI numbers come
from an isolated `emacs -Q` frame, include GC, and are two runs per side.

One hidden buffer stays alive for each language that has been highlighted.

## Known limitations

Fontification itself (`font-lock-ensure`) remains the largest allocator for
code-heavy replies, and the final `buffer-string` copies and table property
publication are unchanged. Pixel measurement of table cells still goes
through `string-pixel-width` once per measured string. The fontification
buffer keeps its mode's buffer-local state between blocks, as Org's does;
mode hooks are still delayed, as before. Emacs 27.1 was not run; the APIs
used (`defvar-local`, `cl-mapc`, `erase-buffer`) exist there.
