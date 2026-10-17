# 113 - Reuse Saved Emacs Authentication in E2E Tests

## Background

The real-server test run after heartbeat recovery commit `d3efa28` failed at
its first RPC with HTTP 401. Running Emacs had remembered a working token via
Customize, but `emacs -Q --batch` deliberately does not load that configuration.
The missing layer was test setup, not the RPC exchange described in 008.

## Decision

Keep discovery in the E2E runner. Reuse existing authentication first; when
none is available, read literal Customize settings from a selected settings
file or the standard Emacs init/custom locations. Match the saved server
address before reusing its token. A token saved without an address belongs
only to the default local server. Scope the recovered option to the test run.

## Why

Loading an entire user init would make a clean test depend on installed
packages, hooks and unrelated side effects. Reading forms without evaluating
them preserves the clean environment while using the token Emacs already
saved. Reader diagnostics are sanitized because they may contain token text.
An explicit settings-file override handles configurations a clean Emacs
cannot discover without evaluating arbitrary Lisp.

The inspected dsh 0.2.0-rc.2 keeps launch tokens in a process-owner WeakMap and
only prints the authenticated URL at startup. Its durable browser credential
is a signing secret, not a launch token. Reading that secret to manufacture
cookies would bypass the normal authentication exchange; log scraping would
also expose unrelated data. Neither is an acceptable fallback.

## Consequence

The ordinary batch smoke command can authenticate without manually copying
a saved token. Existing URL tokens, configured/captured tokens and cookies
retain their behavior. No production authentication code changes, no token
is printed, and the runner does not save settings back to disk. Unit tests
cover literal-only parsing, destination checks, explicit file selection,
existing-auth preservation and setup before the first RPC. The real-server
smoke run passed all 28 checks and archived its temporary sessions.

This record accompanies an uncommitted change on top of `d3efa28`.

## Known limitations

Saved launch tokens can become stale when dsh restarts; callers still need a
current token or authenticated URL then. Computed settings and arbitrary
custom-file assignments are not evaluated: use `DSH_E2E_CUSTOM_FILE` instead.
Tokens and addresses must be in the same settings file; separate files are
not combined into a guessed identity. This does not add discovery to the
production client or alter the interactive workflow recorded in 008.
