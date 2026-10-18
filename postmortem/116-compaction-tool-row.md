# 116 - Automatic compaction summaries use the tool-row chrome

Automatic failure-row spacing is superseded by [121](121-single-attempt-feedback.md).

## Background

At `6eea27c`, the automatic compaction summary from [104](104-auto-compaction-feedback.md)
was a neutral folded fragment with counts and Markdown, but its blank padding
and plain title separated it visually from adjacent tool rows. The user asked
for the same compact presentation as tools, with dsh web as a reference.

The installed dsh web 0.2.0-rc.2 `CompactionItem` uses a compact header and
`IconApiOutlineRegular`, the same terminal-style icon used by bash tools.
It only builds its automatic row after a replacement checkpoint is present.
Emacs renders the earlier summary event, so copying web's "Context compacted"
title would incorrectly imply that checkpoint application had succeeded.

## Decision

Keep the existing automatic summary fragment and its neutral **Automatic
compaction** title. Reuse the bash tool icon and `dsh-emacs-tool-title-face`,
and remove the summary fragment's extra blank padding. Counts remain muted;
the Markdown body remains folded by default and uses the existing disclosure.
Do not add a success tint, success mark, icon asset, face, option or resource
layer. This record accompanies uncommitted work against `6eea27c`, not a change
already contained in that baseline commit.

## Why

The visual difference belongs to the renderer, not the compaction lifecycle.
Reusing the tool icon and title face gives the row the requested shape without
another styling owner. Keeping the existing fragment preserves replay identity,
folding and transcript navigation instead of inventing a parallel card type.

Record 104's semantic boundary remains valid: a generated summary is useful
information, not proof that the replacement was committed. A later failure
must not contradict an earlier success claim.

## Consequence

Automatic summary rows stack like tool rows. Their counts still describe
covered history items and approximate old-context tokens, not savings.
The original conversation remains visible. Manual `/compact` output and the
mode-line `Compacting` activity are unchanged. Automatic failure information
remains a separate card with its existing blank padding.

## Known limitations

This is a summary-row appearance change, not lifecycle consolidation. It adds
no running row, elapsed clock or success/failure state to the summary header.
Missing summary events still produce no summary row; existing history limits
and other compaction behavior from 104 are unchanged.
