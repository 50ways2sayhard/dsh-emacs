# 144 — Zebra-cross table row bands

## Background

The Markdown renderer already defined `dsh-emacs-markdown-table-zebra` and
honored `dsh-emacs-markdown-table-zebra-stripe`, but the face inherited
`default` with no background, so turning the option on changed nothing on
screen. The face was also applied per cell inside
`dsh-emacs-markdown--insert-table-data-row`: the border pipes and the
newlines never received it. Any background added to that face would have
painted cell interiors only, leaving an unshaded gap at every pipe, so the
"stripes" would not read as stripes.

Layer ownership: `dsh-emacs-markdown--render-table-source` decides which rows
are header, separator and zebra; `-insert-table-data-row` emits the pieces of
a (possibly wrapped) row.

## Decision

Zebra rows now carry one background band across the whole rendered row.
`-render-table-source` resolves the band face once per table and passes it as
the `:band-face` argument; `-insert-table-data-row` applies it to each
physical line of the row — first border pipe through last border pipe,
newline excluded — after every inline face, so inline code keeps its own
background. The band color is derived from the active theme at render time;
a `:background` customized on `dsh-emacs-markdown-table-zebra` pins an
explicit color instead. `dsh-emacs-markdown-table-zebra-stripe` still toggles
the behavior.

## Why

- One band instead of per-cell faces: a background applied per cell leaves
  the border glyphs unshaded, and the row still reads as separate cells. The
  point of a zebra crossing is a continuous band across the road.
- Per physical line instead of the whole inserted region: a wrapped row
  contains newlines, and shading them makes a user-customized `:extend` face
  bleed to the window edge on continuation lines only — inconsistent. Never
  banding the newline also keeps the band stopping at the row's right border,
  which matches the table's width instead of widening it across the
  transcript.
- Not the header or separator rows: the header has its own bold identity, and
  the separator is a rule; striping either would fight the visual hierarchy.
- Theme-derived instead of fixed colors: the band is a background, and a
  background that ignores the theme's hue looks like a foreign gray on tinted
  themes. `defface` cannot express "this theme's background, a little
  darker", so the renderer derives it: the frame's `default` background
  blended 8% toward its `default` foreground. Eight percent is strong enough
  to read as a band and weak enough to stay a background on light, dark and
  tinted themes; both ends of the blend are the theme's own colors, so
  contrast is preserved by construction.
- The derived color is an anonymous face value `(:background "#rrggbb")`,
  not a mutation of the named face. Mutating the face spec per frame would
  need `enable-theme-functions` (Emacs 29+; baseline is 28.1) or advice on
  `enable-theme`, would fight `customize-face`, and would repaint every
  buffer that uses the face.
- The named face stays the customization seam: when its own `:background` is
  set (user, theme or `customize-face`) the renderer returns the symbol
  unchanged; otherwise it returns the derived value. Rejected alternatives:
  inheriting a stock face such as `hl-line` (themes may style it as a loud
  selection, and the coupling is semantically wrong); `:inherit default` (a
  `defface` cannot express a blend).
- The face stays last in each position's face list, so an inline code chip
  keeps its own background on top of the band.

## Consequence

- `dsh-emacs-markdown--table-zebra-face` resolves the band per table:
  pinned face → symbol; otherwise the blend, with a neutral light/dark gray
  (`#eaeef3` / `#30353f`) when the frame reports no background. Terminal
  frames answer with the color *names* `unspecified-bg` / `unspecified-fg`;
  those count as "no background" and are never handed to
  `color-name-to-rgb`, which would try to resolve them against a window
  system that does not exist.
- `-render-table-source` passes that value as `:band-face`;
  `-insert-table-data-row` keeps painting each physical line of the row,
  border pipes included, newline excluded.
  `dsh-emacs-markdown-table-zebra-stripe` semantics are unchanged.
- Verified on a GUI frame: the default white theme renders `#ebebeb`; after
  the frame's `default` face was set to One Dark (`#282c34` / `#abb2bf`) the
  band became `#32373f`; pinning the face returned the symbol.
- `docs/ui-styling.md` documents the band, its theme derivation and the
  pinning seam; `CHANGELOG.md` carries the user-visible entry.
- `dsh-emacs-test-markdown-table-zebra-band-crosses-row` pins the
  full-row contract (pinning the face so the band value is the symbol), and
  `dsh-emacs-test-markdown-table-zebra-color-follows-theme` pins the blend,
  the terminal fallback and the terminal color-name guard by mocking the
  color layer.
- Copy/yank is unaffected: the band is text properties, which the existing
  plain-text yank handler strips.

## Known limitations

- A frozen table keeps the color captured when it was rendered; a live theme
  switch repaints tables rendered afterwards, not existing ones.
- The 8% blend ratio is fixed. A user who wants a stronger or weaker band
  sets the face's own `:background`, which opts out of derivation.
- Terminal frames have no theme background to blend, so they get the neutral
  fallback rather than a hue-matched band.
- Batch frames treat colors as bang colors (`color-values` of `#fafafa`
  returns white) and `default` resolves to `unspecified-bg`/`unspecified-fg`;
  the derivation is therefore covered by mocks in the unit suite and by a
  GUI probe, not by a batch render assertion.
- The band stops at the right border. A full-width stripe would need the
  newline banded too plus `:extend t` on the face; deliberately not done
  because the transcript would then look striped across its whole width.
