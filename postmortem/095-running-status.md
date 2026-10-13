# 095 — Running status: whale tail, caption and clock

Asset packaging superseded by [098](098-embedded-whale-data.md).

## Background

At `e961d93`, dsh's busy status used a per-buffer progress-bar timer. Pending
mode-line work added the web whale tail through `image-animate`, initiated
during mode-line evaluation. That left two animation owners and depended on
image animation's display updates reaching the mode line. The tail was also
too subtle on its own, so the web's accompanying text was requested in its
English `Deep diving · 12s` form.

## Decision

Render the running status as one cached mode-line string, played through one
buffer-owned `dsh-running` slot in the shared animation scheduler: sixty
explicit GIF image indices over three seconds, the `Deep diving` caption with
a narrow foreground sweep, and a whole-second elapsed clock. Remove the old
progress-bar counter/timer and native image timers. Keep the larger logo; Doom
animates its existing tail, and native mode lines replace the progress bar
with the same animation. Timing and rendering stay in the modeline module;
base and peak colors belong to the faces module.

## Why

An indexed image descriptor is ordinary cached mode-line output: redisplay
does not initiate animation, and playback stays independent across sessions
even though scheduling is shared. A public redisplay callback lets dsh keep
the pending-text batching decision from 037 without coupling the animation
package to chat state, and repeated busy snapshots leave playback time
intact.

Readable text makes the running state apparent even when the small tail's
movement is missed, and whole-second elapsed time supplies useful waiting
context. Foreground-only changes preserve character widths, and the clock
itself does not shimmer. A local running-start timestamp separates elapsed
work from looping visual time, so the clock does not reset on repeated
running snapshots. Doom must append its segment face rather than replace all
faces, or the character-level sweep is erased.

Asset inspection also found a conversion defect: the earlier GIF kept prior
pixels while transparent areas moved, accumulating trails. Rebuild full masks
from the web APNG with background disposal for every frame, then compare all
sixty decoded masks and delays against the source, and keep the converter and
MIT notice so the asset can be reproduced. A per-buffer `image-animate`
scheduler was rejected because it would give the mode line a second animation
owner whose display updates the mode line does not control.

## Consequence

Start/end, disconnect, buffer death and mode changes govern slot ownership; no
animation timers remain after the last slot stops. Hidden buffers skip
rendering, and active slots adopt theme colors on their next tick. Running
mode lines show the caption in native and Doom layouts; idle ones restore
their prior labels. Terminals show the same caption and clock without the
color sweep. Two faces control the base and peak foregrounds; equal colors
make the caption static. Tests cover frame selection, palette tint, disposal,
repeated running snapshots, single Doom placement, step visibility, caption
formatting, face preservation and independent session cleanup.

This records uncommitted work based on `e961d93`. Web source reference:
`deepseek-harness` commit `5badb15009`,
`packages/client/ui-chat/src/client/chat/RunningWhaleTail.tsx` and its APNG.
GUI probes checked native/Doom output, frame decoding, frame progression,
theme recoloring, one shared timer and zero native image timers. The running
GIF and the idle SVG use an 18×18 display box; the GIF keeps its native 28×28
frames and is scaled into that box.

## Known limitations

GIF transparency is binary, so translucent APNG edge pixels become opaque;
motion, silhouettes and timing are retained, not exact antialiasing. Elapsed
time measures the current local observation of running state, not an
authoritative server turn duration: disconnect or reopen resets it, and the
reply footer remains the server-based duration surface. Terminals and builds
without GIF support show cycling text. Timers are cooperative, so delays can
skip visual frames or seconds, and text width can grow as elapsed time gains
digits. Per-window colors for the same buffer across unlike displays remain
outside this change.