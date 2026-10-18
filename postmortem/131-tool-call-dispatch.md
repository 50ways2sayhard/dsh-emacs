# 131 — Decode tool-call data and flatten rendering dispatch

## Background

At `3c4f069`, tool-call rendering repeatedly reads the event data while
selecting a Plan card, todo snapshot or ordinary pending card. A single-use
todo renderer reads those same fields again. This records the tenth
refactoring batch based on that commit, following the tool-result
boundary in [123](123-decoded-stream-and-tool-results.md) and preserving the
snapshot model in [022](022-fragment-snapshots.md).

## Decision

Decode tool-call data into `dsh-protocol-tool-call`, then select the rendering
branch in one flat conditional. Inline the todo state update and row insertion
into that branch and delete `dsh-emacs-render-todo-write`, which had one caller
and no documented command or customization surface.

## Why

The data view gives protocol ownership to name, call id and arguments while
removing repeated lookups from rendering. Flattening the branches removes an
early-return macro and makes the todo visibility exception explicit. Moving
the entire renderer or adding an application wrapper would add indirection
without separating another responsibility.

The existing tool-result view also accepts data rather than a whole event.
Using that same boundary keeps sequence and timestamp handling in place;
there is no need for a generic durable-event model to simplify this dispatch.
Arguments remain opaque because tool variants already own their interpretation,
and hidden calls must not start parsing malformed argument JSON.

## Consequence

No commands, defaults or presentation change. Visible Plan documents use their
existing card; absent or blank documents use ordinary pending cards. Hidden
calls return nil without advancing the anchor, but todo snapshots still render
and return their sequence. Missing todo call ids still use the sequence fallback.
Ordinary card state, folding and timestamp construction are unchanged.

Behavior tests were run against the old implementation first. They distinguish
the Plan/ordinary branches and protect hidden-call and todo sequence behavior.
Protocol tests protect string/symbol keys and opaque argument identity. The
architecture map records the narrower boundary.

## Known limitations

Other durable payloads, the outer event envelope, and tool-specific argument
JSON and metadata remain separate work. Decoding all three fields at entry may
raise an error earlier for an improper/dotted alist that a hidden call formerly
left partly unread; such an object cannot come from the wire JSON reader.
The Emacs 27.1 baseline is unchanged; validation here uses Emacs 31.1.50.
