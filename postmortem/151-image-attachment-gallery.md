# 151 — Transcript image attachments use a web-style thumbnail gallery

## Background

The user asked for dsh web's image rendering, with images allowed to sit at the
bottom of the message, and for a lone image to use the same compact style as a
multi-image gallery. Web renders user attachments through `ImageGallery`
before the bubble (`ui-chat`'s `UserContent`): a lone image gets a 240px box,
several images become 64px square tiles. This client rendered every image block
as its own line at 40% of the window width with no height bound, so a message
with two screenshots stacked full-width pictures and dominated the transcript
(`dsh-emacs-render--attachment-image` used only
`dsh-emacs-markdown--image-max-width`).

The transport and protocol were not involved: `user/message` image blocks,
inline base64 and `session/attachment` fetches already worked, and the failing
layer was the renderer's layout.

## Decision

- Keep attachments below the message text. Web places the gallery above the
  bubble; the user accepted bottom placement, and bottom keeps the authored
  text first in a top-to-bottom Emacs transcript.
- Do not copy web's two-size policy. Every image block, in a message with one
  image or several, renders as the same compact thumbnail
  (`dsh-emacs-render-image-thumbnail-lines`, 4 text lines) packed into rows
  that fit the window, with the user rail's five columns reserved. Web's
  larger lone-image box is deliberately not used; clicking still opens the
  full picture.
- Thumbnails are aspect-fit inside a square box rather than cropped. The box
  is measured in text lines (`frame-char-height`), so it follows the font
  instead of a hardcoded pixel size.
- The `[image …]` placeholder remains the single source of identity: the
  async fill-in still finds each slot by `dsh-emacs-image-id` and puts the
  `display` property over it, so inline bytes show immediately, refs show when
  `session/attachment` settles, and terminal Emacs keeps readable text.
  `RET` / `mouse-1` opens the original through the existing keymap, and each
  placeholder now carries the file name as `help-echo`.
- One new `defcustom` under `dsh-emacs-render` owns the height. No protocol,
  fetch, composer or option surface changed.

## Why

The visible defect was layout, so the fix belongs in the renderer and reuses
the existing image spec, keymap and asynchronous slots rather than adding a
second image path. Web's square tiles are produced by `object-fit: cover`;
Emacs has no equivalent crop for a `display` image, and stretching a screenshot
to a square would distort exactly the details these attachments exist to show.
Aspect-fit accepts non-uniform tile widths in exchange for not lying about the
picture.

Keeping one size for all image counts follows the user's explicit preference
and removes a branch: a transcript that mixes one-image and many-image
messages keeps a consistent visual weight, and the larger lone-image box would
make a single screenshot an outsized block again. The cost — a lone image is
smaller than web's single variant — is accepted because the thumbnail remains
recognizable and `RET` / click opens the original.

A fixed 64px tile was rejected: Emacs image sizes are frame pixels and the
character height varies with font, display scale and theme, so 64px would look
large in one setup and tiny in another. Expressing the bound in text lines
keeps the gallery proportionally stable.

Manual row packing was chosen over letting `word-wrap` reflow a single long
line: the chat buffer enables `word-wrap`, but relying on it would couple the
gallery's structure to a user-visible wrapping setting, and the existing
transcript is not reflowed on resize anyway.

## Consequence

- Every user-message image reads as one compact thumbnail below the text; a
  lone image no longer expands into a large bounded picture.
- File attachment chips are unchanged and still render one per line after the
  image rows; content order within images and within files is preserved, but a
  file authored between two images moves after both.
- The optimistic echo and canonical render share the layout because both go
  through `dsh-emacs-render--insert-user-block`.
- `docs/customization.md`, `docs/architecture.md` and `CHANGELOG.md` document
  the option and the layout.

## Known limitations

- No cropping, so a very wide panorama becomes a short, wide thumbnail instead
  of web's uniform square crop; every thumbnail preserves the whole picture.
- A single-image message is deliberately much smaller than web's single-image
  variant; full detail requires opening it.
- Row breaks are computed when the message renders; resizing the window does
  not repack an existing gallery (consistent with the transcript's general
  no-reflow behavior).
- Assistant image content blocks are still ignored by the assistant renderer;
  web draws them in place. Only user message attachments changed here.
- In a terminal, images stay `[image: name]` placeholders; several may share a
  line, and `word-wrap` decides where the text rows break.
