# 136 — Require Emacs 28.1

## Background

Every file header declared `Package-Requires: ((emacs "27.1"))`, a baseline
chosen when the package started. That claim had not been exercised for a long
time: the protocol and rendering refactors recorded "Emacs 27.1 实机验证未执行"
in [126](126-context-and-permission-decoders.md) through
[135](135-rpc-response-boundaries.md), and day-to-day validation runs on
Emacs 31.1.50.

The first CI run (commit `ef6f34f`) made the gap concrete. The Emacs 27.1 job
failed the unit suite with hundreds of `void-function (setf plist-get)`
errors: the generalized-variable expander for `plist-get` exists in Emacs 28.1
but not 27.1, and the renderer, plan, markdown and history modules use
`(setf (plist-get ...))` in 40 places. Earlier, `ensure-list` (28.1) had
silently shipped in the slash-command path and `string-search` (28.1) in the
test suite; those were only patched because CI had not yet run. The checker
also needed an explicit `(require 'seq)` for `seq-subseq` on 27.1.

## Decision

Raise the minimum to **Emacs 28.1**. Update every `Package-Requires` header,
README, AGENTS, current docs and the CHANGELOG, and change the CI matrix from
`27.1 + 30.1` to `28.1 + 30.1`. No compatibility shim is added; 27.1 users
stay on 0.6.x.

## Why

28.1 is the true minimum the code already requires: the `plist-get` setter and
`ensure-list`/`string-search` all arrive there. Keeping 27.1 would mean
rewriting 40 `setf (plist-get ...)` sites to `plist-put` (or shipping a `gv`
expander shim), plus a permanent compatibility layer for an Emacs released in
August 2020 — exactly the "delete, don't deprecate" debt this tree avoids.
Debian 12 ships Emacs 28.2, so 28.1 keeps that distribution.

29.1 was the alternative. It would let later work drop the pre-29 pixel and
`yank-media` branches, but those guards are small and already tested; cutting
Debian 12 users now is not worth the cleanup. 28.1 is the smallest honest
raise.

## Consequence

`Package-Requires` is 28.1 in every `.el`, and the CI matrix, README, AGENTS,
CHANGELOG (`Breaking Changes`, 0.7.0) and current docs say so. The now-unused
`dsh-test--ensure-list` / `dsh-test--string-search` helpers are gone, native
`ensure-list`/`string-search` are used again, and the slash-command path calls
`ensure-list` directly.

Version-guarded code for 29+ (`buffer-text-pixel-size`, `yank-media`) and 31+
(`completion-table-with-metadata`, `string-pixel-width`) stays: those branches
still serve 28.1–30.x. A separate fix keeps `yank-media-preferred-types` from
being shadowed on 31 and from being referenced on earlier versions.

## Known limitations

The 28.1 job is the first runtime validation on that version; local validation
remains Emacs 31.1.50. GUI and real-server E2E stay manual. Older postmortems
and released CHANGELOG entries still mention 27.1 as historical context and
are not rewritten.

CI evidence: run `39130860451` (`ef6f34f`) failed on 27.1 with the
`setf plist-get` errors that motivated this record.
