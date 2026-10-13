# 097 — Verify the animated path, and stop stubbing built-in functions

## Background

The running-status work (095, 096) is only half verified without Motion Line.
The client's suite gates the animation tests behind `(featurep 'motion-line)`,
so `scripts/verify.sh` skipped them and asserted only the static fallback; and
the tests that did run against an engine pinned time and visibility with
`cl-letf` on the built-in `float-time` and `get-buffer-window`.

Both assumptions broke at once.  `test/dsh-test.el` sets
`comp-enable-subr-trampolines` to nil in its header to avoid a gcc trampoline
during batch runs.  With that setting, natively compiled code calls those
subrs directly, so the stubs were silently ignored: `motion-line-play`
recorded the real clock while `motion-line--tick` read the stubbed one, so
elapsed time clamped to zero, the cached frame never changed, and the
redisplay callback never ran.  An isolated probe passed, because a default
Emacs keeps subr trampolines enabled — only the suite's own setting exposed
it.  Four tests failed on an installed (natively compiled) engine, and nothing
in the gate ran them.

## Decision

Add the missing seam in the engine and exercise both configurations in the
gate.  Motion Line now exposes `motion-line-current-time-function` and
`motion-line-visible-p-function`; every playback control, tick and render
decision reads them (rationale: that repository's `postmortem/002`).  The
client's tests bind those variables instead of stubbing built-in functions,
and `scripts/verify.sh` runs the suite a second time against an engine when one
is available — preferring the sibling `../motion-line` checkout, then
`DSH_MOTION_LINE_DIR`, then an installed package — and prints a skip when none
is present.

## Why

A variable read cannot be direct-linked away, so the seam holds in interpreted,
byte-compiled and natively compiled builds whatever the host does with subr
trampolines.  Moving the seam into the engine keeps the fix where the coupling
is: dsh-emacs owns batching (`motion-line-redisplay-function`) and the engine
owns time and visibility, instead of the client reaching into the engine's
scheduler or faking window state.

Coverage had to fail loudly rather than skip.  096 deliberately let the gate
run without an animation package, so absence still skips; a *stale* install is
different, and the suite now reports "predates the clock/visibility seams"
rather than silently verifying nothing.  Preferring the sibling checkout
matches where the engine is developed and keeps a stale installed copy from
standing in for the working tree.

Rejected alternatives: **keeping the subr stubs** (they do not reach compiled
code, which is the whole bug); **displaying the test buffer with
`set-window-buffer` and driving the frame from a local variable** (works, but
leaves the client faking the engine's clock and window state); **vendoring or
pinning the engine** (096 rejected a bundled copy and keeps the dependency
optional).

## Consequence

`scripts/verify.sh` has a second unit-suite pass, `dsh-test-motion-line`, that
skips when no engine is found.  `docs/modeline.md` documents the preference
order and the seam requirement.  Client tests bind engine variables and keep
`cl-letf` only on dsh's own interpreted `float-time` clock.  Later changes to
the animation path should keep defining timing through the engine's seams, and
must not reintroduce stubs on built-in subrs.

## Known limitations

The suites are coupled across repositories: the integration tests need an
engine at least as new as the seam change, and an older install fails the
second pass.  The engine's own suite still stubs `message` and `run-at-time` by
function cell; that is safe under its own `scripts/verify.sh`, which leaves
subr trampolines enabled, but it is the same class of fragility and would need
its own seams before running against a host that disables them.  The e2e
scenario still drives the animated path only when the engine is on the batch
load path.

This records uncommitted work based on `e961d93`; the engine change is
uncommitted in the sibling checkout based on `a45547a`.