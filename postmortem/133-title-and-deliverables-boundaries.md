# 133 — Decode title and deliverables at their owning boundaries

## Background

After the stream decoder work in `364cecb` (baseline `845325e`), events still
borrowed the renderer's generic field reader to inspect session titles.
Deliverables also mixed wire validation with collection of files for a
turn's closing row. These were remaining payload boundaries, not transport
or display failures.

## Decision

Decode session title events and deliverables in protocol. Events retains title
application and refresh recording; rendering retains file merging, links and
turn-tail placement. Remove the renderer's deliverables extraction helper and
the events declaration for its generic field reader.

## Why

A title view distinguishes a matching event with a nil title from an unrelated
event. Returning only the title string would silently change refresh recording
for absent titles. Deliverables retain duplicate paths and wire order because
last-description-wins merging depends on the existing sequence of declarations.
Pairs are sufficient for file entries; per-file structs would add accessors
without clarifying this boundary.

## Consequence

No commands, options or valid-wire display behavior change. Empty file lists
and unusable turn ids still return the original sequence. Protocol tests cover
both key styles, absent titles, duplicate files and invalid entries. Existing
render and lifecycle tests cover title synchronization and deferred file rows;
the render entry also accepts the decoded view through the existing compat gate.

## Known limitations

The deferred migration below is completed by [134](134-event-consumer-boundaries.md).

This is not the final event migration. Outer metadata, message content,
assistant chunks, turn failure payloads and tool-specific arguments/results
still have renderer consumers. A generic field-reader relocation would leave
those consumers interpreting wire shapes, while an eager universal event view
could change when unrelated fields are validated. They need their own semantic
boundaries. The events sequence gate still uses the renderer's sequence helper.
