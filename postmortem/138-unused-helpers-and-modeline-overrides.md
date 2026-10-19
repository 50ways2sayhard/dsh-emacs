# 138 — Remove unused helpers and mode-line overrides

## Background

At `2917c10`, the entry point still declared the former tooltip question
reader's symbols and duplicated the protocol array normalizer. Several
modules retained unused forward declarations and required the fragment UI
without consuming its definitions. The session list now requires `subr-x`
directly for its utility macros instead of relying on fragment UI loading.
HTTP callers went through an identity
wrapper for authentication headers despite already loading the server owner.

The mode-line cwd and branch setters had no production callers, but maintained
override state in detection, rendering and cache keys. The uncalled teardown
also combined local overlay cleanup with removal of globally shared Doom
segments. The usage predicate was referenced only by a test.

## Decision

Delete the unused declarations, UI dependencies and forwarding helper; use
`dsh-protocol--list` for array normalization and the server's header function
directly. Remove the redundant authentication-function existence guards in
the entry point, which already requires the server module.

Remove the public Lisp functions `dsh-emacs-modeline-set-cwd`,
`dsh-emacs-modeline-set-branch`, `dsh-emacs-modeline-teardown` and
`dsh-emacs-usage-p`, without aliases. Remove the override variables and the
teardown-only Doom unregistration helper. Stop printing mode-line setup
internals each time a chat opens.

## Why

The gain is fewer state sources and dependency edges, not new modules or
helper layers. Cwd comes from the chat's `default-directory`; branch detection
uses that directory and keeps the existing TTL cache. Tests exercise that
live branch path instead of a private override.

Do not wire the dormant teardown to a chat's exit hook: its global Doom
unregistration would affect other open chats. Deleting an unused function
preserves the existing lifecycle rather than introducing that behavior.

## Consequence

The four public Lisp function removals are breaking changes for external
callers, even though the package never calls them. Record them under 0.7.0
Breaking Changes; current mode-line documentation describes the remaining
state sources. Existing chat commands, input, rendering, authentication and
animation cleanup retain their behavior. This decision records the working
change based on `2917c10`; no commit is created automatically.

## Known limitations

This cleanup does not redesign mode switching or add overlay cleanup hooks.
Global Doom registration remains package-scoped. Transport extraction and
other package-wide `fboundp` guards are outside this change. Source reload
retains removed definitions in a running Emacs; restart for their complete
removal, as documented in [115](115-source-hot-reload.md).
