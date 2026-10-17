# 118 - ERT subsystem tests with a non-exiting runner

## Background

The unit suite at `9cf020d` executed assertions while loading one large file.
Its private result collector could not select or rerun an individual case with
ERT. Conditional pass-only assertions also needed a source-scanning integrity
check. [006](006-new-session-project-workspace.md) records an earlier false
success: destructively reversing the result list erased failures before the
exit status was calculated.

Splitting that file alone would leave both problems intact. Coverage also
loaded the suite directly and depended on successful tests returning control
so it could print a report afterward.

## Decision

Use named ERT tests in owner-specific `test/dsh-test-<subsystem>.el` files,
with shared fixtures in `test/dsh-test-support.el`. Keep `test/dsh-test.el` as
the thin loader and the existing batch command. Loading a subsystem only
registers tests; execution belongs to ERT, not file loading.

The runner selects the `dsh-unit` tag, rejects an empty selection, and returns
ERT statistics without exiting. Its batch entry point owns process status.
Coverage suppresses that entry point, runs the same function, reports, then
exits from the unexpected-result count. Isolated subprocess tests verify both
entry points with tiny passing, failing, and broken fixtures.

## Why

ERT supplies assertion diagnostics, failure accounting, selection, and reruns
without a second testing framework. Converting pass-only branches to
unconditional assertions fixes the absence of evidence rather than preserving
a parser that guesses which assertions should have executed. Related checks
can share one local fixture while still reporting their assertion context.

The load/run boundary serves two current callers: developers selecting tests
interactively and coverage retaining control after a failure. An unconditional
`ert-run-tests-batch-and-exit` at suite load would break coverage; keeping the
old collector alongside ERT would retain the failure mode being removed.
Testing process statuses in fresh Emacs instances checks the external contract,
including an early failure followed by a passing test, rather than trusting
that a printed failure reaches the shell.

Independent and repeated runs exposed state hidden by the old load order:
mutable quoted fixtures, unscoped histories and optional frontend variables,
and a queued submission that escaped its RPC stub and sent a real request.
Fix these at the owning fixture rather than adding a global reset framework.
Capability-specific SVG and yank-media assertions get their own tests so
skipping them cannot hide the surrounding clipboard or Composer checks.

## Consequence

The batch command remains `emacs -Q --batch -l test/dsh-test.el`. Developers
can load an owner file and select a test with `M-x ert`; fixtures must not rely
on prior cases. The syntax gate discovers subsystem/support files, and the
verification gate runs independent runner/coverage self-tests. E2E and GUI
entry points are not discovered as unit subsystems.

Optional Motion Line behavior remains as decided in
[096](096-standalone-motion-line.md) and [097](097-engine-test-seams.md): absence
skips animation cases, but an incompatible installed engine fails. The batch
runner scopes its native-trampoline setting to execution rather than changing
a developer's setting when tests are loaded.

This records uncommitted migration work based on `9cf020d`.

## Known limitations

ERT registration alone does not prove an assertion is reached. New tests still
need unconditional assertions and local cleanup, and optional dependency skips
must not disguise broken installations. The runner self-tests use tiny fixture
suites to verify loading, selection, reporting, and exit codes; the full unit
suite remains responsible for product behavior. Coverage is informational and
keeps its explicit product-file scope, correcting the stale footer filename
to modeline and excluding protocol structs because of testcover's
object-copying limitation. Other modules remain outside that instrumentation
scope; the Emacs 27.1 baseline is unchanged.
