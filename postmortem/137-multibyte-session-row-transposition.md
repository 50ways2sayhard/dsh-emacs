# 137 — Safe multibyte session-row transposition

## Background

CI at `8ec4b2b` crashed inside Emacs 28.1 and 30.1 during the session-list
regrouping test. Syntax, compilation and clean loading passed. The row updater
from [078](078-session-list-row-updates.md) moved a row by transposing it with
an empty, non-adjacent region at its destination.

Emacs bug [70122](https://lists.gnu.org/r/bug-gnu-emacs/2024-04/msg00158.html)
describes incorrect byte/character lengths in that native transposition path.
The 30.1 source passes a byte length to character-based interval operations.
A minimal three-row reproduction also exposed corrupted text in the local
31.1.50 build. Switching to adjacent regions alone did not fix that build:
after moving `v: scaling` before `a:` and `b: ℓ₀`, line-end-position returned
7 instead of 11 even though buffer-string initially showed the correct text.
Subsequent row diffs then corrupted the buffer.

## Decision

Transpose the row with the contiguous block between its destination and its
old position. After the move, republish the destination character's existing
text properties with set-text-properties before further position lookups.
Keep the row-bounded diffs and marker-preserving movement from 078.

This records uncommitted work based on `8ec4b2b`; the failing GitHub run is
[39132281055](https://github.com/vritser/dsh-emacs/actions/runs/39132281055).

## Why

Adjacent regions avoid the older native interval bug while producing the same
row rotation. The property write preserves the character's metadata but
invalidates stale position information on the affected development build.
Merely setting the buffer modified flag or narrowing it did not repair the
position lookups. This is a deliberate compatibility workaround at the native
editing boundary, not a replacement for correct Emacs internals.

Deleting and reinserting rows would lose external navigation markers. A
whole-buffer diff would restore the performance problem documented in 078.
Skipping the crashing test or changing CI versions would leave users exposed.

## Consequence

The regression checks exact multibyte text, row properties, and markers at row
starts and inside multibyte text, including an advancing marker. The existing
regrouping test still covers workspace ordering, bounded diffs, insertion,
collapse and expansion. No workflow or minimum Emacs version changes.

## Known limitations

The redundant one-character property publication is compatibility debt. It is
kept independent of a version cutoff because development snapshots can differ;
remove it only after the supported builds pass the mixed-width regression
without it. This does not fix transpose-regions for other Emacs callers.
