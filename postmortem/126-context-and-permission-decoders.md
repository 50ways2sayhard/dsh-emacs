# 126 — Share context decoding and decode permission values

Partially superseded by [127](127-control-projection-boundary.md): control
payloads now decode at their enclosing boundary; permission consumers take
the decoded scalar directly.

## Background

At `3c4f069`, live context and permission consumers in events read nested wire
fields through the renderer's accessor. The session constructor separately
walked the same context object three times. [125](125-follow-snapshot-protocol-boundary.md)
left these nested projection payloads with their existing consumers.
[005](005-context-window-server-snapshot.md) records why context samples come
from the server, and [050](050-permission-preset-control.md) separates the
displayed permission value from the selectable catalog.

## Decision

Use one context protocol struct for raw pressure, projected estimate and
window. Reuse its decoder in session rows and live consumers while preserving
the existing session fields. Decode a permission projection directly to a
nonempty string or nil. Events retains buffer selection and display updates.

This records the fifth refactoring batch based on `3c4f069`.
It changes decoding ownership without changing commands, defaults or display
policy. The outer projection and core control boundaries remain separate work.

## Why

Context has three related values shared across module boundaries, making a
protocol struct useful. Its decoder preserves the values; choosing a usable
display sample belongs to the consumer. The current list path uses integer
raw pressure, while live updates prefer positive projected usage once raw
pressure is positive. Sharing the parser must not silently unify these rules.

Permission has only one useful scalar. A one-field struct would add wrapping
and accessors without improving the model. Its decoder owns the wire field,
string validation and empty-value handling; it does not trim names or validate
against catalog options. The existing event boundary still accepts raw input,
so there is no extra scalar/raw compatibility layer.

## Consequence

The events module no longer reads the fields inside either payload, and
session construction no longer repeats the context traversal. Context uses
the existing `dsh-protocol--struct` gate; both raw fixtures and decoded values
reach the same target-buffer consumer. Outer list checks are redundant because
the decoders already handle non-object input.

Zero-pressure samples and empty permission values continue to preserve the
old display. Architecture and modeline docs describe the decoder boundary and
the existing list/live distinction; this also corrects an oversimplified
projected-versus-pressure description in the current modeline docs.

## Known limitations

Core control still parses projection keys, session ids and baseline envelopes.
Goal and inbox already have decoders, but their missing-value and explicit
clear semantics must remain distinct when the outer boundary is migrated.
This change adds no new freshness policy or client-side context accounting.
