# 149 - Separate turn folding from activity groups

## Background

The task-work design introduced by `2d1b0db` and recorded in
[142](<142-task-work-details.md>) had one outer disclosure. Reports of unfolded
stopped work and mid-turn clarifications exposed a mismatch between that model
and Web's independent turn, activity, atomic-detail and file-result layers.
This was a rendering-model problem, not a transport or redisplay defect.

Static inspection of the installed `@deepseek-ai/dsh-client-ui-chat` bundle,
version `0.2.1-rc.2`, established the intended default policy. The detailed audit
is in [Web folding reference](<../docs/web-folding.md>).

## Attempts and corrections

The first attempt allowed failed and stopped turns to fold without a final
answer, under `Failed` or `Stopped`. A real-history replay verified the stopped
second turn, but not the user's later visible problem: a completed fourth turn
with mid-turn input. Matching Web's captions did not mean matching its policy;
Web keeps the outer process open for failed and stopped turns.

The second attempt split work around human messages into disjoint overlays
controlled by one task summary. It preserved input and final-answer visibility,
but still hid intervening explanations under the wrong level of disclosure.
Both approaches were discarded in favor of separate local activity groups.
Acceptance must inspect the exact affected turn and compare the full hierarchy,
not merely show that the originally suspected round now folds.

## Decision

Implement the default `detailed + completion` core using existing rendered
fragment boundaries, decoded call IDs/names, and per-turn activity ownership.
Running turns stay flat at the activity level. Once a turn closes, contiguous
thinking, tool and automatic-compaction cards form independent activity groups;
assistant replies, human input and process-external rows separate them.
Compaction is a member, not a boundary or a tool category count.

Successful turns without interleaved input may additionally fold their whole
process, retaining any final text answer outside it. No final answer is required
if process content exists. Stopped, failed and interleaved-input turns instead
have non-foldable status headers. Terminal diagnostics, deliverables and reply
actions stay outside the process fold. Activity summaries count distinct calls,
rank categories with stable ties and use Web's English joining rules.

Keep atomic card identity and original transcript text. The renderer owns both
disclosure levels' lifetimes; the UI owns one contiguous overlay per disclosure.
Do not retain the discarded disjoint-span machinery as a compatibility path.

## Why

Visible fragments already provide ordering and boundaries without a second
event projection or copied card bodies. Protocol identities supply categories
without parsing labels or wire fields in the renderer. Explicit per-turn
ownership preserves older-page extension, late results and independent card
choices, and permits complete cleanup on reset or trimming.

The key distinction is what each control hides: a whole process, one contiguous
activity, or one card body. One cross-input turn control cannot substitute for
several local activity groups while keeping explanations visible.

## Consequence

Live/history/prepend regressions, nested disclosure tests, late-tail updates,
tool-only trim ownership and the full repository gate passed. Real turn-2
history reproduced the screenshot's three summaries with all replies visible.
The existing Emacs buffer also verified the open interleaved turn, final answer,
active-turn safety and preserved drafts, history cursors and window selection.
A later screenshot exposed compaction incorrectly splitting a group; treating
it as a member restored Web's combined category ordering, with the summary
still inspectable after expansion. These are buffer-state checks, not measured
redraw timing.

This consolidates three uncommitted draft records. `2d1b0db` is prior-design
evidence, not a commit of this implementation. The user-visible changes are
listed in the [0.7.0 changelog](<../CHANGELOG.md>).

## Known limitations

Only the default core is implemented, not four selectable modes or `next-input`.
Manual group/card choices remain preserved rather than reproducing Web's
outer-hide resets and answer-step generations. Counts omit PTC-only recursive
children without decoded call identities. Existing attempt diagnostics and
non-tool cards remain; final-answer boundaries are text-based. Host-backed
`ChangedFiles` is not added. Automatic compaction retains its earlier summary
row rather than claiming that the replacement checkpoint has succeeded.

If trimming crosses an active turn's start, the retained tail loses its work
boundary and later live events do not reconstruct it. That tail can remain
flat until history is rebuilt. Correct rebasing across partially retained
fragments is deferred, not covered by the Web-alignment acceptance tests.
