# 128 — Decode follow projections at their late application boundary

Superseded in part by [129](129-core-workspace-boundary.md): core routing and
workspace payloads now decode in protocol; the follow decision remains intact.

## Background

At `3c4f069`, events read follow projection fields through the renderer's
accessor. [125](125-follow-snapshot-protocol-boundary.md) decoded the opening
snapshot but left its projection block raw. [127](127-control-projection-boundary.md)
then separated control projection decoding from application. This records the
seventh refactoring batch based on the same commit.

## Decision

Use a dedicated, flat follow projection view. Decode it at the existing late
application point, after history and the assistant prefix. Events keeps the
application order: one subagent batch, title, context, permission, goal and
questions. Plan remains in the earlier snapshot phase.

## Why

Follow and control use the same payload decoders but different absence and
routing rules. A missing/null follow goal clears the old row; a non-object
goal is skipped. A separate goal-update flag retains that distinction without
wrapping each cell. An empty question struct carries an absence watermark;
nil means no question update. Follow questions apply to the current chat,
without requiring an entry in the chat registry. Inbox has no follow consumer.

Reusing the control consumer would introduce policy branches or change these
rules. Eager decoding in the opening snapshot would also make a later
migration-required error prevent history and assistant state from applying.
The small dedicated view removes wire knowledge from the consumer while
preserving this phase boundary, without callbacks or deferred objects.

## Consequence

No command, default, reader or repaint policy changes. Raw fixtures and typed
views use the existing `dsh-protocol--struct` gate. The snapshot still carries
the raw block until the late decoder; this is intentional sequencing, not
permission for event consumers to inspect its fields.

Tests cover missing versus skipped goal updates, absent question watermarks,
the subagent batch, ignored Plan/inbox cells and application after history.
Existing tests retain question settlement on resumed cards and newer live
Plan/question updates received during history rendering.

## Known limitations

As in 127, a block is decoded before any of its consumers run. Malformed
goal/question payloads can fail before earlier subagent/title updates in that
block take effect. History, cursor and assistant prefix still apply first;
transport code still reports errors. The existing subagent decoder's errors
for malformed non-list values and its symbol-keyed contract remain intact.

Workspace/`$events` routing and durable event payloads still have raw fields
in their consumers. This change does not introduce a universal event model
or raise the Emacs 27.1 baseline.
