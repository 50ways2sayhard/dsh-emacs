# 122 — Remove inactive transcript options and group bookkeeping

Synthetic-event limitation superseded by [123](123-decoded-stream-and-tool-results.md).

## Background

At `3c4f069`, the renderer still allocated activity-group IDs, counted calls,
searched for group headers at turn boundaries and isolated those counters
during history rendering. The UI no longer created group headers or attached
child fragments, as recorded by [022](022-fragment-snapshots.md). Its renderer
cleanup remained outstanding.

`dsh-emacs-assistant-divider` had a similar mismatch: its only reader was the
uncalled private `dsh-emacs-render--insert-divider` function. Both Custom
options appeared configurable while having no effect on the transcript.

## Decision

Remove `dsh-emacs-group-consecutive-tools`, `dsh-emacs-assistant-divider` and
the unused divider writer. Delete group state, lifecycle calls and history
bindings. A tool call writes its tracked state once, and a late question
answer no longer saves and restores an unrelated completed-group count.

This records changes based on `3c4f069`. README, customization,
UI styling and architecture describe the resulting behavior; CHANGELOG lists
the public option removal under 0.7.0 Breaking Changes.

## Why

Removing the state reduces the number of lifecycle rules a renderer change
must preserve. Moving the bookkeeping or keeping aliases would retain a
public promise with no implementation. Implementing grouping would add a new
workflow rather than simplify the existing independent tool cards.

Shared group and divider faces remain: workspace headings and tool bodies
still use them. Their names alone are not evidence of dead code.

## Consequence

Personal configuration must drop the two removed options. Transcript spacing,
tool visibility and per-card folding retain their existing behavior. Existing
tool, question, plan, history and streaming tests protect those paths; no
new rendering state or compatibility seam is introduced.

## Known limitations

Late question settlement still constructs a synthetic tool-result event.
Replacing that wire round trip belongs to the separate normalized tool-state
work in [decision 123](123-decoded-stream-and-tool-results.md). Source reload
does not unbind removed definitions, so restart Emacs for full removal, as
specified by [115](115-source-hot-reload.md).
