# 132 — Decode command events and reuse optimistic cleanup

## Background

At `3c4f069`, command rendering reads wire fields directly, duplicates the
optimistic cleanup function, and calculates a new label and icon even when
settling an existing row. The run/done branches are nested inside that shared
setup. This records the eleventh refactoring batch based on that
commit, following [131](131-tool-call-dispatch.md).

## Decision

Decode the consumed command fields into `dsh-protocol-command-event`. Keep
row creation setup in the run branch, reuse the existing optimistic cleanup,
and destructure the stored row when applying a result.

## Why

There should be one owner for deleting a pending row, stopping its animation
and clearing its tracking state. Both submit rejection and live run takeover
already require that operation; another cleanup implementation can drift.
Run-specific setup obscured the done branch's actual source of identity: its
existing row, not the incoming result's name.

The event view owns wire interpretation without introducing another renderer
or a new state model. It deliberately omits command arguments because rows
show only names. The `commands/execute` RPC response has a different envelope
and admission role, so combining it with durable run/done events would make
both consumers interpret optional fields unrelated to their job.

## Consequence

No command, option or display behavior changes. Only live runs take over the
pending submit row. Historical rendering neither starts nor stops animations,
preserving [044](044-load-older-history.md). Completion keeps the run's label
and icon, with the existing error classification and folded result body.
Hidden commands, missing ids and orphan results still return their sequence;
the visibility check remains before payload decoding.

The takeover test now fails if its optimistic setup is missing, instead of
conditionally skipping every assertion. Behavior checks were run on the old
implementation first; protocol tests cover both key styles, unmodified result
text and unknown outcome kinds. Architecture and refactoring notes track the
new boundary. Production code is smaller despite the added protocol view.

## Known limitations

The shared command-row list and local shell lifecycle stay as they are;
neither needs a new abstraction for this change. Other durable payloads and
outer event metadata remain separate migrations. For visible events, eager
field extraction can fail earlier on improper/dotted alists; such objects
cannot be emitted by the wire JSON reader. Emacs 27.1 remains the baseline,
with this batch validated on Emacs 31.1.50.
