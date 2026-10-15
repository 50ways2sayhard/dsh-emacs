# 102 — Queue actions require confirmed identity and safe content

## Background

Review of the staged Next Message actions in 101, based on `79cadfd`, found
three gaps. The queue owner's idle send-now path removed an item and submitted
only its text, losing attachments. Composer kept button closures when a new
queue struct changed only placement. It also offered actions on the local
optimistic preview, whose `local-...` ID was never a server queue identity.

## Decision

Keep the text-only idle resubmit, but reject attachment-bearing items before
any removal or local mutation. Put this guard in the queue owner so Composer
and the manager share it. Running turns still accept steering by item ID.
Composer includes placement in its render signature and withholds action
cells for its queue owner's optimistic submit object until confirmation.

## Why

The queue mirror retains a text preview, not the original attachment payload.
Reconstructing that payload from the preview cannot preserve a message. A
guard fixes data loss without introducing another prompt-submission pipeline.
Object identity distinguishes the local preview without treating a string
prefix as a server-ID contract. Placement belongs in the signature because
the captured item determines what send-now does, even when its text is stable.

## Consequence

Idle send-now reports an error and leaves an attachment-bearing item queued.
Newly submitted messages remain visible but gain buttons only after the host
confirms them. Tests cover both placement transitions, confirmation restoring
actions, rejection before any RPC, busy attachment steering, and idle text
resubmission. The README, queue customization, styling and architecture docs
describe these boundaries. This records the uncommitted review fixes to 101.

## Known limitations

There is still no attachment-preserving idle send-now path. Adding one needs
the original content and a submission contract that retains it; until then,
keeping the queued item is preferable to silently discarding its attachments.
