# 120 - @ suggestions follow the session list's visibility

## Background

[010](010-at-references.md) made the @ menu offer every session the host's
`sessionReferenceResolver/candidates` returned;
[119](119-reference-completion.md) replaced its matching but kept that
candidate set, so the menu also offered the sessions the tree never shows:
archived sessions, blank (never-messaged) sessions and subagent-origin child
sessions.

Blank sessions are the visible symptom. The host labels a session with its
latest title and falls back to the session id, so a blank session appears as
`@session-emacs-<sha256>` (the id form `dsh-emacs-new-session` mints) or as a
bare uuid — indistinguishable from an archived leftover. `session/list` keeps
those rows out of the tree through `dsh-emacs-session--visible-p` (not
archived, not subagent origin, not blank unless it is the open session, per
dsh web's browser rule), while @ offered every candidate the host
returned.

## Decision

The new `dsh-emacs-reference--visible-candidates` gate applies the session
list's own rule to session candidates. Archived ids are dropped first through
the synced archive registry, so they stay hidden even when the list cache does
not know them; then candidates whose session the `session/list` cache marks
blank or subagent-origin are dropped via `dsh-emacs-session--visible-p`. A
candidate whose id is not in that cache stays offered, so a cold cache only
degrades to the archive filter. The raw reference cache is never rewritten:
unarchiving or a first message restores a row without a fetch.

## Why

The list is the client's definition of a session the user has; an @ row for a
session that cannot appear in the tree is noise, and blank or untitled rows
read as archived debris. Filtering at display time keeps discovery host-owned
(the host still ranks candidates, no re-ranking or extra request), needs no
wire change, and reuses the one visibility rule instead of duplicating it.

The rejected alternative is grouping subagent sessions in the @ popup, the way
dsh web's reference UI does (the installed
`@deepseek-ai/dsh-client-ui-reference` renders them under a `Subagents`
section): that is a larger UI change for rows the user almost never wants to
reference, while the noise complaint is about rows being offered at all. The
other rejected alternative, filtering blank/subagent sessions in the host
resolver, would change discovery for every client and cannot use the client's
view of what the tree shows (the currently open session, workspace
membership).

## Consequence

`@` completion and `M-x dsh-emacs-reference` offer only sessions the session
list would show, plus sessions the list cache does not know yet (for example
one created since the last `session/list`). Subagent sessions can no longer be
referenced from `@`; the subagent catalog remains their UI. Archiving and
unarchiving still apply to hidden rows: `M-x dsh-emacs-archive-session`
completes over the cached session list, not the visible subset. References
already inserted in a draft are unaffected.

`dsh-emacs-reference--visible-candidates` is the single gate for both entry
points, so a later change to the visibility rule belongs in
`dsh-emacs-session--visible-p` (its owner) rather than here.

## Known limitations

Visibility is sampled from the client's `session/list` cache: before that
cache is fetched the archive registry is the only filter, and a session created
after the last refresh stays offered until the next refresh. A blank session
that receives its first message appears on the next `@` completion, not while
an open popup is showing (the completion table rebuilds its presentation
snapshot per invocation). The host's candidate limit still applies before
filtering, so hiding rows can yield fewer than the limit suggests.

This record accompanies the commit that adds the visibility gate on top of
`c353867` (the reference-completion overhaul recorded in
[119](119-reference-completion.md)).
