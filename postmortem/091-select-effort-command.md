# 091 — A dedicated reasoning-effort command

## Background

Reasoning effort was reachable only as the second reader of the model picker
(`C-c C-m`, `dsh-emacs-select-model`): after choosing a model, a mini-prompt
asks for its effort and sends `session/selectModel` with a `reasoningEffort`
field. Two consequences made the control feel absent:

- an empty RET ("keep the current model") returns before the effort reader, so
  changing *only* the effort required navigating back to the running model's
  row and re-picking it;
- the mode-line `effort` segment was display-only
  (`dsh-emacs-modeline-set-effort` is not a command), and the host registers no
  `/model` or `/reasoning` slash command to fall back on.

The missing behaviour therefore belonged to the model-picker surface in
`dsh-emacs.el`, not to the transport, protocol or mode-line modules. The code
at `95772df` already carried every part the command needs:
`dsh-emacs--session-model-selection`, `dsh-emacs--model-effort-choices`,
`dsh-emacs--model-effort-default-id` and `dsh-emacs--model-pick-effort`.

## Decision

Add `dsh-emacs-select-effort`, bound to `C-c C-e`, as a peer of
`dsh-emacs-select-model`. It keeps the standalone-effort read in a private
`dsh-emacs--select-effort-prompt` helper (session-id plus the raw
`session/modelCatalog` response), mirroring the model picker's split between
the command and its prompt. Both live in `dsh-emacs.el`; no other module
changes.

## Why

The command reuses the running session's `modelSelection` projection for
(provider, model) and falls back to the catalog host `default` exactly as the
model picker does, so it never needs the model row the picker asks for. All
effort semantics — option order, name fallback, default precedence, the
no-`reasoning` case — stay in the existing helpers instead of being
reimplemented. Sending `session/selectModel` with the same provider and model
plus a new `reasoningEffort` is the host's only write path for effort, and is
already what "re-pick the current model" does. `C-c C-e` was free (a test
asserted it unbound).

Alternatives rejected: a `/reasoning`-style slash command would need host
support and a registry entry, while the RPC path already exists; making the
mode-line effort segment mouse-clickable would help only GUI users and add a
second, different entry point.

## Consequence

`C-c C-e` and `M-x dsh-emacs-select-effort` change a session's reasoning effort
without touching its model; the mode-line `effort` segment updates on success.
`C-c C-m` keeps offering effort as the second step of a model switch. A model
without `reasoning` options reports `Model … offers no reasoning-effort
options` and sends no RPC. `README.md` (key table and model paragraph),
`docs/model-picker.md` and `docs/customization.md` describe the new surface, and
`CHANGELOG.md` links back here. Unit coverage: request payload with the running
provider/model, current-effort pre-selection, mode-line update, the keybinding,
the no-options error, C-g cancellation and the catalog-default fallback.

## Known limitations

The command needs the active session and a running (or catalog-default) model;
it cannot choose an effort for a session that has never run and whose catalog
carries no default. Provider/model resolution matches only the reference
provider, so a model id offered under several providers follows the session's
own provider. No effort history or per-preset effort memory is added.