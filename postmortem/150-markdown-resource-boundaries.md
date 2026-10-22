# 150 — Markdown resource syntax owns file targets

## Background

The audit starts at `9fe1b60` plus the uncommitted angle-image fix. A valid
`![alt](<path>)` exposed several independent boundaries: the emphasis/code
passes could rewrite filename characters before URL extraction; regexes
stopped at the first parenthesis or included a title in the target; links and
images disagreed on URI decoding; missing local files fell through to the
browser. A bare `.png` fragment could freeze an image before a later chunk
appended `.more`, and the final event did not repair that property.

The installed dsh Web 0.2.1-rc.2 was inspected, not reimplemented. Its
micromark destination tokens use string parsing, separate from emphasis. Its
local-file parser percent-decodes once and accepts `#L24` / `#L24-L30`; HTTP,
HTTPS and mailto are its external-link whitelist. Chat images use session
cwd, whereas document-preview images use the previewed file's directory.
Web serves local bytes through its authenticated file endpoint; Emacs reads
its own filesystem. Those execution environments are not interchangeable.

## Decision

- Keep resource parsing in the existing Markdown owner. One bounded inline
  scanner captures label/target positions and the authored destination for
  both links and images. The URL is never recovered from already-styled text.
  Rendering and code protection must agree on single-line boundaries.
- Strip resource syntax without replacing its label wholesale. Finish label
  styling before freezing the rendered resource; preserve the outer target
  of a linked image. Temporary render metadata does not become another
  persistent transcript/cache layer.
- Share local path validation between Markdown links and images. Separate
  navigation suffixes before one URI decode. File authorities are empty or
  localhost only; reject controls, malformed escapes, remote/UNC paths and
  unsupported schemes before local access. Missing files stay local errors.
- Retain Emacs's native `file:` and colon-line syntax and add character-column
  positions. Web parity is not a reason to remove useful editor navigation.
  Capture the rendering directory for click closures. Do not apply URI rules
  to literal `@` references or deliverable paths, whose owner remains the
  reference module ([012](012-reference-links.md), [041](041-deliverables-row.md)).
- Treat a bare path as literal text until its complete line or final message
  establishes the image boundary. Backtick runs close only with an equally
  wide run, and styling deletes delimiters rather than body text so existing
  avoid markers survive.

## Why

More image-specific regexes or resolver fallbacks would preserve the ordering
bug: an already-damaged filename cannot be repaired by filesystem lookup.
Rebuilding every final reply to clear stale display properties would hide the
partial-line bug and undo the bounded-stream work. Destination ownership fixes
both without another renderer, render cache or timing workaround, consistent
with [036](036-bounded-stream-markdown.md) and [108](108-markdown-allocation.md).

The first destination-protection implementation split style passes at every
URL. Follow-up comparison found that it regressed emphasis surrounding a link
(`**see [file](url) now**`). That approach is not the final model: strip valid
resource syntax before ordinary styling and retain protection only where raw
resource syntax remains. Labels and enclosing prose both need their original
styling context.

## Consequence

Regression coverage uses real temporary paths, invokes rendered RET commands,
and checks image/keymap properties in the actual stream renderer. Plain text
equality alone cannot detect stale image displays or wrong click targets.
The user-facing contract is in [reference.md](../docs/reference.md#assistant-markdown-file-links).
Acceptance on macOS Emacs 31.1.50 opened the expected file at line 2,
character column 3 after changing the invoking buffer's directory, decoded a
real PNG to 320 x 285 pixels and opened its exact punctuation-bearing name.
The hidden-frame probe verified that existing chat points/content ticks and
the selected window were preserved; it did not measure visual flicker.

## Known limitations

This remains a bounded, single-line resource renderer, not a full CommonMark
AST. Multiline resources, reference-style definitions and destination HTML
entities are not resolved; entity-bearing resources remain literal. Bare
parentheses are bounded at 32 levels. A limited standalone local image path
with spaces remains compatible, but angle destinations are preferred. Titles
are parsed without being displayed. Multi-line inline code spans are not
implemented. Remote images are not fetched, and native image decoding and its
error placeholders remain Emacs's responsibility. Windows path spelling does
not make a POSIX host capable of opening a Windows drive.
