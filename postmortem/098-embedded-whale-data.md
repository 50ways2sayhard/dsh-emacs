# 098 — Embed the whale animation in Elisp

## Background

The pending running-status integration based on `e961d93` loads a small GIF
relative to the modeline library. Review caught the image missing from the
staged files; a source-only installation could make the same omission. The
user requested embedding after comparing the packaging tradeoff.

## Decision

Keep the converted GIF as a Base64 constant in `dsh-emacs-modeline.el`, decode
it on first use, and cache the unchanged binary mask. Tint copies as before.
Remove the separate GIF. Retain its MIT notice in the source and provenance
in `assets/dsh-whale-tail.md`. The converter emits the replacement Elisp
constant after verifying all sixty frames and their delays.

## Why

An 8,521-byte mask becomes 11,364 Base64 characters, a small source-size cost
for removing a runtime file-path dependency. A separate resource module would
add another file that installers must remember. Lazy decoding avoids doing
image work for terminals and installations without Motion Line.

## Consequence

Source and byte-compiled installations carry the same animation without an
assets directory. A fresh-process test copies only the client Elisp files and
checks lazy decoding, the mask checksum, cache reuse and independent tinting.
Regeneration against the original APNG must reproduce the embedded constant.
This records uncommitted work based on `e961d93` and supersedes the separate
asset packaging in [095](095-running-status.md).

## Known limitations

Base64 is not readable artwork; reviewers should use the converter and source
checksum. GIF binary transparency, frame timing and display size are unchanged.
