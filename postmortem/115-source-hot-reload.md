# 115 - Reload source without resetting live chats

## Background

The user requested one command to apply all local package changes in an
already-running Emacs. Work begins from committed baseline `d96a449`, with the
separate, uncommitted queue mode-line removal documented in
[114](114-remove-queue-modeline.md). This record concerns the reload workflow,
not that display removal; `d96a449` is not the reload implementation commit.

Loading only the entry point leaves already-provided modules untouched.
Re-entering the chat mode is worse: it rebuilds the input area and resets
pending messages, attachments and renderer state. Disconnect/reconnect and
renderer teardown also finalize or discard live stream state. Those are not
safe substitutes for applying source definitions.

## Decision

Add `dsh-emacs-reload` in its own module. Read every local package source first,
reject unreadable forms and literal top-level package-require cycles, then load
explicit `.el` paths in dependency order. The default directory belongs to the
loaded reload module; Lisp callers may supply another local checkout. This
bypasses stale bytecode without unloading features or restarting the server.

Keep ordinary `defvar` and Custom values, live buffers, drafts, attachments,
processes, transports and timers. Refresh declared keymap contents in place
and face default specs beneath user overrides. Refresh Composer, session-list
and mode-line presentation and their visual caches, not the transcript.
Use named deferred callbacks for optional icon registrations.

Refuse during active minibuffer/question/approval interactions, pending session
creation or history loading. Do not reject ordinary streaming or cancel its
callbacks. Add no default keybinding, server RPC or prompt submission.

## Why

Most long-lived callbacks use named functions or small delegates to them;
replacing function definitions already updates their future calls. Preserving
resource ownership avoids dropped input, duplicate subscriptions, cancelled
shell commands and a misleading idle state while the host still works.

Existing buffers and text properties retain keymap objects, so replacing map
contents is more useful than rebinding map variables. Presentation caches need
invalidation when code or embedded assets change. These are bounded reload
needs, not a reason to invent a generic resource registry or migration engine.

## Consequence

After saving source edits, run `M-x dsh-emacs-reload`. An older running Emacs
must first `M-x load-file` the new reload module; updating the checkout alone
does not change that running session. Personal ad-hoc edits to package keymaps
must be reapplied after reload. Current options and Custom face overrides stay
in effect. The queue indicator removed by 114 disappears when its new shared
mode-line composition runs; deleting its obsolete runtime definitions is not
required to stop displaying it.

## Known limitations

This is not transactional live migration. Preflight catches syntax and
package dependency cycles, but evaluation failures can leave some new
definitions installed. Fix the error and reload again, or restart Emacs.

Removed definitions stay resident. Existing transcript text and in-flight
lexical callbacks are not recreated, and existing objects do not acquire a new
struct layout. Restart for complete definition removal, changed struct layouts
or changes that require major-mode initialization. External packages are not
reloaded. These limits are explicit rather than hidden behind destructive
teardown or a claimed rollback.
