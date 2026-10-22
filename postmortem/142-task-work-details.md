# 142 — Fold completed task work details

## Background

At `1dcdb5d`, individual tool and thinking cards could fold, but a completed
task still left every intermediate reply and card header in the transcript.
The requested workflow is dsh-web-style work disclosure with the final answer
left visible. This is a new presentation feature, not a revival of the unused
consecutive-tool grouping removed in [122](122-remove-inactive-transcript-options.md).

The first implementation, based on `1dcdb5d`, passed constructed turn fixtures
and a GUI toggle probe but failed in the actual chat: the default 30-message
tail omitted `turn/start`, so the fold never appeared, and Think, tools and
final prose appeared twice around the Copy/Fork footer (buffer identities
showed the same final message sequence twice). Two layers owned the defects:
the fold eligibility rule assumed a complete turn, and the transport
re-entered frame parsing while rendering yielded.

## Decision

Enable `dsh-emacs-fold-work-details` by default. After successful completion,
put the work before the final prose answer behind one Work details button.
The renderer determines eligibility from decoded, sequence-ordered turn facts;
the UI hides the original region with an overlay and preserves individual
card folds.

Bound the fold by the earliest loaded event for that turn, captured before
rendering, and require successful completion plus eligible final prose — not a
fully loaded task. Earlier pages extend the existing disclosure without
resetting a manual choice. Turn-start timestamps still own duration
accounting. This record accompanies the uncommitted change based on `1dcdb5d`,
recorded in the [0.7.0 changelog](../CHANGELOG.md).

Serialize frame consumption in the WebSocket transport. Reentrant filters may
append input but cannot drain it while another consumer dispatches; advance
the exclusive byte cursor before dispatch and trim the latest input once on
exit. Keep the rendering yields and linear parsing design from
[016](016-streaming-work-and-transport-liveness.md); do not compensate by
changing UI timing or skipping pending records against a newer anchor.

## Why

Copying the work into a parent fragment would destroy child identity and make
late tool results, question settlements, links and nested folds target stale
text; an overlay leaves those owners intact. Reusing per-turn reply facts
avoids a second event-history store, but final-answer eligibility must stay
separate from the footer Copy target: earlier prose is still a useful Copy
target when a later step has no final answer.

A complete successful turn is positive evidence for hiding work; failure,
interruption or interleaved human input is not. The default history contract
is a message-aligned tail, not a complete turn, so a missing start is normal
rather than evidence that completed visible work must stay open. Batching
history reconciliation lets an older page complete the evidence without
changing a reader's explicit expansion choice.

The transport previously retained the current frame during dispatch.
Rendering a snapshot yielded after five events; a socket read could then parse
that same frame recursively. The nested pass inserted the footer, and the
outer pass rendered its remaining tail again. A single snapshot plus one newer
incoming event reproduces it; the server need not send duplicates. The
consumer, not the renderer, owns wire ordering and the incomplete byte tail.

## Consequence

Users get a compact transcript while questions, final answers, deliveries and
reply actions remain visible. RET or click toggles the work; setting the option
to nil and refreshing restores the flat layout. Full refresh resets folds;
trimming releases overlays whose start boundary was removed. Tests cover live
and replayed completion, partial-history merging, streaming Markdown, draft
safety, independent tasks, reset and unsafe completion cases. A regression
covers loading older tasks while the oldest visible task is still active: its
start must advance past the prepended page, or its later fold can absorb an
older final answer; the page renderer owns that marker adjustment.

A real 264-record page beginning at sequence 742, with no turn start, folds
its completed work while keeping final sequence 1002 visible. The live server
E2E suite passes its connection and rebaseline checks. A GUI connected to the
same real session verified a single final-answer region after cold open and
reconnect, and exposed a leading SVG icon escaping invisibility; the collapsed
overlay now supplies an empty display replacement and removes it when
expanded.

## Known limitations

This adds completion-time folding, not the web client's configurable deferred
next-input timing or step-level detail modes. A task without a proven final
prose answer stays open. The disclosure covers the contiguous work before the
first final-answer segment; reasoning interleaved between final-answer text
segments remains visible. Manual fold preferences are buffer-local and are
not persisted across a full refresh or reopening Emacs.

Reloading code preserves existing transcript text; `C-c C-r` reconnects and
only renders unseen sequences. Neither removes duplicates already painted nor
reconstructs older fold facts. Reopen the chat buffer after preserving any
draft to rebuild it from server history. Server records are unchanged.
