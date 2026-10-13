# 096 — Standalone Motion Line: sibling repository, name and optional load

## Background

The generic playback engine started as a prototype inside this client. Keeping
it here would tie an independently useful library to dsh's release cycle, and
the provisional name Kineline (kinetic + mode line) did not say what the
package was for. A bundled copy under `packages/` was tried while no release
existed; it forced deliberate copy synchronization, and removing it later made
loading fail before chat could start.

## Decision

Ship the engine as an independent sibling repository, `motion-line`, with its
own tests, documentation, license and verification script. Use `motion-line`
for the repository, package, feature and API prefix, and drop the provisional
`kineline-*` names without aliases before the first release. Load it
optionally from `load-path`: when it is absent, dsh loads normally and shows a
static `Deep diving` caption during a turn — no animation timer, asset or
elapsed clock — and redraws explicitly on busy-state changes. Errors from an
installed library still propagate.

## Why

Independent testing and installation make the engine usable without this
client, and a descriptive name makes a reusable library easier to recognize;
consistent repository, feature and symbol names make installation and
configuration predictable. Animation enhances the running indicator but is not
required to use chat, so neither a bundled copy nor an implicit package
installation is worth the maintenance cost, and a second spinner or clock
scheduler would duplicate the engine's ownership.

Rejected alternatives: **Kineline** did not convey "mode line"; a **bundled
distribution copy** kept the engine under `packages/` until the library became
loadable, then forced copy synchronization; a **Git submodule** would require
recursive clones and an upstream commit that does not yet exist.

## Consequence

Engine development happens in `../motion-line`. The client's verification gate
needs no animation package: the integration tests run against Motion Line only
when it is supplied on the batch load path, and print a `SKIP` line otherwise.
Native and Doom layouts show the static caption in their existing running slot
and clear it at completion or disconnect; Motion Line users keep the whale,
sweep and clock. A fresh-process regression copies only the client libraries
and checks loading, caption placement, redraws, cleanup and absence of timer or
animated-frame calls.

This records uncommitted work based on dsh-emacs `e961d93`. The independently
published Motion Line implementation is `a45547a`
(`github.com/vritser/motion-line`). Restart Emacs after installing Motion Line
so no old package timers remain loaded.

## Known limitations

The static fallback deliberately omits the running elapsed clock, so step time
can change only on ordinary redraws. Broken or incompatible installed libraries
still report errors; the fallback covers absence only. Compatibility remains
Emacs 27.1, validated with the installed Emacs rather than a complete version
matrix.