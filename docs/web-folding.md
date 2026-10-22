# Web folding reference

This reference audits the shipped `lib/client.js` bundles without browser
inspection. The installed `@deepseek-ai/dsh` and `@deepseek-ai/dsh-client-ui-chat`
packages both report version `0.2.1-rc.2`.

Emacs now implements the default `detailed + completion` core: separate turn
and activity folds, visible reply boundaries, and deterministic group summaries.
The sections below describe Web rules; the final section distinguishes remaining
Emacs differences. See [decision 149](<../postmortem/149-web-activity-folding.md>).

## Four independent layers

| Layer | Owner | Meaning |
|---|---|---|
| Turn process | `TurnProcessNodeView`, `ChatNodeSeat` | Hide work before the final reply, including that reply's reasoning |
| Activity group | `ChatGroupSeat`, `TurnGroups` | Fold a contiguous process range between visible replies or other boundaries |
| Atomic detail | `ToolRow`, `ReasoningRow` | Independently disclose one tool's body or one reasoning block |
| Changed files | `ChangedFiles` | A turn-tail result card, not an activity group or a count of edit calls |

An expanded turn can contain collapsed groups; an expanded group can contain
collapsed tools. Do not flatten these into one shared expanded flag.

## Modes and timing

| Mode | Fold completed turns | Activity groups | Live title detail | Settled reasoning preview |
|---|---|---|---|---|
| `compact` | Yes | Grouped while running and historical | No | No |
| `standard` | Yes | Grouped while running and historical | Yes | Yes |
| `detailed` | Yes | Flat while running; grouped when historical | Yes | Yes |
| `verbose` | No | Always flat | No | Yes |

Ordinary Web defaults to `detailed`; Desktop defaults to `standard`. Independent
timing defaults to `completion`. Saved `normal`/`expanded` resolve to `detailed`.
Atomic details start closed even in `verbose`; flat groups do not open bodies.

With `completion`, an eligible successful turn folds when it closes. With
`next-input`, the latest loaded exchange stays open by default until new input,
not merely the last turn or a viewport position. A pending transcript input with
a request ID disables deferral. History uses the same defaults, and a matching
manual turn choice overrides them; replay does not open everything.

## Turn eligibility

| Situation | Outer process behavior |
|---|---|
| Running | Always open; settled-turn header is absent |
| Successful, with final reply | Fold work and reasoning; retain the final response outside |
| Successful, no final reply | Still foldable if there is visible process content; all such work can fold |
| No process content | Header is disabled; nothing can be disclosed |
| Aborted or interrupted | `Stopped`; outer process always open, but local groups can fold |
| Error | `Failed`; outer process always open, but local groups can fold |
| Interleaved input | Outer process always open; disclosure disabled, without a chevron |

The final reply must be the last step's finalized assistant content, contain
visible reply material, and contain no tool-call block. Nonblank text, images,
and other non-reasoning/non-tool blocks qualify; reasoning alone does not.
Without a final reply, `answerStep` and `answerAnchorSeq` are null; a nonempty
reasoning-only process can still fold.

`canCollapse = foldable && hasContent && !turnProcessAlwaysOpen(node)`.
Interleaved input forces open state and makes `hasContent` false. It includes
visible input-level nodes after the opening input, not only a literal user role.
Successful headers say `Completed` or `Completed in ` plus duration;
stopped/error headers omit duration.

## Activity boundaries and titles

A group is not one step or one tool category. Collect process nodes in display
order; flush at assistant responses, explicit process-or-outer group-tree
boundaries, or timeline discontinuities. Reasoning joins the group; response
stays outside. Turn closure closes all groups. In `detailed`, closing one group
does not fold it while its turn is still running.

Automatic compaction is a process member, not a group boundary. Its row hides
with the activity; expanding the activity exposes the compaction's own summary
disclosure. It contributes no category count, so tools on both sides are ranked
together. Web creates this node only after the replacement checkpoint exists;
Emacs retains its earlier `Automatic compaction` summary row, without claiming
checkpoint success, and includes that row in the activity.

For closed groups, recurse through roots and subcalls, deduplicate by `callId`,
and count calls per category, including failed/stopped calls. Sort descending by
count; ties retain first appearance. Reasoning contributes no count. Show
categories, not counts or filenames:

| Tool names | Category | Exact completed label |
|---|---|---|
| `read` | read | Read files |
| `read_image` | readImage | Read images |
| `grep`, `glob`, names ending `_inspect` | search | Searched code |
| `write` | write | Wrote files |
| `edit`, `apply_patch` | edit | Edited files |
| `bash`, `pwsh`, `exec_command`, `write_stdin`, `terminal_*` | commands | Ran commands |
| `run_code` | code | Ran code |
| `web_search` | webSearch | Searched the web |
| `web_fetch` | webFetch | Visited web pages |
| `subagent`, `subagent_*` | subagents | Coordinated subagents |
| `todo_write`, `create_goal`, `update_goal`, `get_goal` | plan | Updated the plan |
| `ask_user_question`, `request_user_input` | questions | Asked questions |
| Everything else | tools | Called tools |

Zero categories yields `Analysis completed`; one uses its unchanged label.
Two use `First and second`; three use `First, second, third` without `and`.
More than three show only the first three plus `, etc.`. Subsequent labels
lowercase only their first character. These exact examples follow:

- `Read files, ran commands, searched code, etc.`
- `Edited files, ran commands, called tools, etc.`
- `Updated the plan and ran commands`

Each `etc.` means at least four categories, not four calls. The last example
has exactly two. These are deterministic summaries, not model text. A live group
names the latest running activity or `Analyzing the request` without one;
preparing calls have preparation labels. Standard/detailed append bounded
argument detail. The atomic reasoning row is titled `Think` instead.

## Manual state and resets

- Turn choices are session-scoped memory keyed by turn and answer step; a new
  answer step invalidates the old choice. These are not Host settings.
- Groups/details start closed and retain choices while the same keyed component
  remains mounted. Remounting resets them; flat mode does not set group open.
- Tool settlement or reasoning completion does not close a manually opened
  detail. Preparing tools cannot expand; other tools need body content.
- Closing only an activity group preserves its nested detail choices.
- Actually hiding the outer turn closes groups and advances node disclosure
  generations, resetting nested tool/reasoning details to their defaults.
- Reasoning previews remove `**`: settled previews use the first line;
  streaming previews advance to completed paragraph first lines.

## Changed files and sources

`ChangedFiles` uses a Host summary announced by `workspace/changes`, when code
diffs are enabled and the summary contains files, not tool counts. Headings are
`Edited {count} files` or `Edited {basename}` for one file. Up to four rows stay
visible; only more than four gets a show-all/collapse toggle. Heading/row clicks
open diff review, not disclosure. `Edited 4 files` is not an activity summary.

Chat source modules: `presentation-policy`, `chat-settings`, `stores`,
`chat/ChatNodeSeat`, `ChatGroupSeat`, `TurnProcessNodeView`, `use-disclosure`,
`ReasoningRow`, `step-process` (`processTitle`), and `conversation-nodes/` modules
`process-activity`, `process-groups`, `turn-process`, `turn-process-presentation`.
`@deepseek-ai/dsh-client-ui-tool` owns `ToolRow`/`ToolCallTree`;
`@deepseek-ai/dsh-client-ui-deliverables` owns `Deliverables`/`ChangedFiles`.

## Remaining Emacs differences

- Only the default `detailed + completion` core is implemented; there is no
  four-mode selector or `next-input` policy.
- Manual group/card choices remain preserved. Web's outer-hide child reset and
  answer-step generation invalidation are not implemented.
- Summaries count decoded `tool/call` identities, not PTC-only child tools.
- Existing attempt diagnostics/non-tool cards remain; not all Web Nodes are reproduced.
- Final-answer boundaries use text replies; image-only projection is not added.
- The Host-backed `ChangedFiles` card is not implemented in this change;
  existing deliverables behavior is unchanged.
