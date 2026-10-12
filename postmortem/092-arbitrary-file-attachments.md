# 092 — Arbitrary file attachments (raw upload route)

Submit input consumption and its undo lifetime are superseded by
[093](093-consumed-input-undo.md); the upload route, receipt lifetime and file
rendering remain in effect.

## Background

Attachment support was image-only, and deliberately so: an image rides
`session/prompt` inline as `{type:'image', mediaType, data: <base64>}`, and
`dsh-emacs-attach-file` / `dsh-emacs--dnd-attach` filtered every candidate
through `dsh-emacs--file-attachment`, which returns nil unless the file's
media type is in `dsh-emacs-attach-media-types`. Dropping a PDF or a log onto
a chat buffer answered "No supported image files among the dropped files."

The wire has carried arbitrary files since dsh 0.1.5
(`docs/rpc.md` §4.17): a file is admitted into a prompt as a one-time
**receipt** — `POST /api/session/uploadFileBinary?sessionId=…&name=…` with the
raw bytes as `application/octet-stream`, answered by
`{ok:true, value:{receiptId, file:{attachmentId, name, bytes}}}` — which then
travels as `{type:'file', receiptId}` inside exactly one prompt's `content`
(valid only in the session it was uploaded for). The host replaces it with the
durable `{type:'file', attachment}` block as the `user/message` is admitted.
dsh-emacs called none of it (§11's unused table).

Three properties of the receipt decided the design, and each rules out the
obvious shortcut:

- **A receipt is one-time and bound to the submission**, so it cannot be
  minted when an attachment is staged: a draft that is cancelled, restored by
  a failed submit, or re-sent would carry a spent authority.
- **The upload is a round trip**, so it cannot be a side effect of prompt
  composition: `dsh-emacs--submit-plain` composed `content` synchronously and
  cleared the input as it started the RPC.
- **The raw route aggregates the whole body** (`url-request-data`), unlike the
  web's streaming fetch, so the size of a file this client will accept is a
  client-side policy, not a wire fact.

## Decision

Staged attachments gained a second kind — a **file entry**
`((file . PATH) (name . N) (bytes . B))` carrying metadata only — and
`dsh-emacs--submit-prompt` became the single place that resolves a staged list
into tagged wire parts. When any entry is a file it uploads every file first
(sequentially, through the new shared `dsh-emacs--http-post`), then dispatches
the message with `{type:'file', receiptId}` parts; otherwise it dispatches
immediately with the inline image parts. `dsh-emacs--submit-plain`,
`dsh-emacs--submit-deferred` and `dsh-emacs-command-execute` now take resolved
parts (plus the staged list for rollback) instead of building parts
themselves, `dsh-emacs-command--submitted-attachments` is deleted, and
`dsh-emacs-attach-file` / `dsh-emacs--dnd-attach` go through the new
`dsh-emacs--attachable-file` (image inline, else file entry). The renderer
gained `dsh-emacs-render--file-placeholder`, and a canonical or optimistic
`user/message` file block renders as a display-only `[file: name · size]` chip.

## Why

- **Upload at submit, never at stage.** The staged entry keeps the path, so a
  restored draft re-uploads and gets a fresh receipt; nothing holds a
  one-time authority across drafts.
- **One resolution point.** Previously the tagging of an image into
  `{type:'image'}` lived twice (prompt content and the command's
  `submittedAttachments`), and the command path could only ever carry the one
  attachment its caller happened to pass. Resolving once in
  `dsh-emacs--submit-prompt` removed `dsh-emacs-command--submitted-attachments`
  entirely, made the command path carry any number of mixed parts, and gave
  file receipts a single place to enter.
- **The raw route for every file, no base64 branch.** `fileUploads/upload`
  takes canonical base64 inside the RPC envelope; the raw route takes the
  file's own bytes. Using it for all files means one code path, no base64
  encoding of a large file, and byte-exactness (the body goes to
  `url-request-data` unibyte, verified live: the host stored exactly the bytes
  and the size the client reported). A size cap
  (`dsh-emacs-attach-max-file-size`, 32 MiB) exists because this client
  necessarily aggregates the body in memory — the web's streaming upload is
  not available to `url-retrieve`.
- **The draft is consumed before the upload, once.** The send command consumes
  the staged set, and `dsh-emacs--submit-prompt`'s file branch clears the input
  before the first round trip, so the send feels immediate and a second
  `C-c C-c` during the upload cannot resend the same text. The ordinary submit
  paths still clear after their optimistic echo, and the `input-consumed` flag
  tells them this draft is already gone, so a newer draft typed while the
  upload ran is left alone. A failed upload restores the consumed draft and
  its staging.
- **The file is rechecked at upload time.** A staged path may have been deleted
  or grown since composition, so the upload revalidates readability and
  `dsh-emacs-attach-max-file-size` before reading, and a local failure becomes
  a failed upload that restores the draft instead of a half-sent message.
- **The optimistic echo is shaped like the durable block.** The canonical
  `user/message` that matches a pending echo is not rendered again, so the
  echo must already carry name and size. Each upload records the receipt's
  durable file reference as `uploaded-file` on this submit's copy of staging
  (the original entry keeps its local name and byte count for a retry), and
  the echo builds `{type:'file', attachment:{name, bytes}}` from that
  reference.
- **`dsh-emacs--http-post` extracted rather than a second copy.** The upload
  and every RPC share the response plumbing (status plist, stale-cookie 401
  drop, GC threshold, buffer restore, C-g-swallowing dispatch); the two
  callers now differ only in URL, content type, body and what they read out of
  the decoded JSON.

Rejected alternatives: using `fileUploads/upload` (base64 in the envelope) for
small files and the raw route above a threshold — two paths to test, and the
base64 path's only advantage is unusual deployments; staging the receipt at
`C-c C-a` time — breaks the one-time/draft-restore semantics above; a new
`dsh-emacs-attach-files` staging command — the existing one-shot and
drag-and-drop entry points already cover it, and staged files are reachable
because `dsh-emacs--stage-attachments` accepts them; making the received chip
clickable — a stored file has no read path of its own (`session/attachment`
is images only, and the durable ref carries no host path), so a link would
have nothing to open until `workspaceFiles` is adopted.

## Consequence

`C-c C-a` (`dsh-emacs-attach-file`) attaches any readable file; a file over
`dsh-emacs-attach-max-file-size` is refused before it is read. A drag-and-drop
takes any files. `C-c C-d` and the composer row say "attachments". The
transcript shows `[file: name · size]` for a file block — including one
received from another client — and the composer help text counts attachments.
The staged-set signature still carries names only, so uploading a file never
repaints the row. `docs/architecture.md` (composer/attachments), `README.md`
(Attachments section and key table) and `docs/customization.md` describe the
new surface; `CHANGELOG.md` links back here. Unit coverage: entry kinds and
the size cap, the upload request (URL, `application/octet-stream`, exact
bytes), receipt parsing, route error and transport failure, staged-order
resolution and short-circuiting on failure, the `session/prompt` content shape,
echo chip, draft restore, and the display-only file chip. Live acceptance
(scratch probe against the running 0.2.0 host): the raw upload returned a
receipt whose name and byte count matched, the prompt carrying it was
accepted, the durable `{type:'file'}` block appeared in `session/page`, and a
forged receipt was rejected with `session/attachment-invalid`.

Later changes must keep the receipt lifecycle in mind: never stage a receipt,
never reuse one, and never add display-only fields to a wire content part
(the optimistic echo builds its own blocks for that reason).

## Known limitations

Received file chips are display-only: `session/attachment` serves images, and
a durable `FileAttachmentRef` carries no local path, so reopening stored bytes
has to wait for `workspaceFiles/readBytes` (which also returns a multipart
body for binaries). Files upload sequentially, one request each, with a
`Uploading …` message as their only progress feedback, and each request
aggregates the whole file in memory — hence the default cap. `commands/execute`
still sends whatever parts it is handed: a slash command whose descriptor does
not declare `input.attachments` is rejected by the host, and the command line's
caption stays in `line`, so a command carrying a file does not echo the file
into the transcript the way a message does.