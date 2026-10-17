# 117 - Keep one footer across consecutive replies

## Background

At `6eea27c`, with the staged compaction styling recorded in
[116](116-compaction-tool-row.md), each completed textual turn retained a
visible footer under the rules in [084](084-reply-footer.md) and
[086](086-reply-footer-turn-tail.md). A main answer followed by an unsolicited
child-triggered reply therefore showed two Copy/Fork rows with no visible
human message between them. These were distinct turns, not duplicate events.

The user chose one visible footer across such consecutive replies. Web's
hover-revealed older actions are not this policy: Web still retains per-turn
footers. This record accompanies the uncommitted Emacs visibility change,
not a change already present in the baseline commit.

## Decision

Between rendered human messages, keep only the footer of the latest
completed turn with a nonempty committed text reply. A newly eligible turn
replaces earlier footer chrome in that group, not earlier reply text or
per-turn facts. Unfinished turns and turns with no visible committed text do
not replace the current footer. Goal notices and hidden subagent traffic do
not count as human-message boundaries.

Copy and Fork continue to target the selected turn's last text reply. Tokens
and duration still describe only that turn; neither actions nor statistics
aggregate across the group. The retained row still follows the turn's full
content, as decided in 086.

## Why

The apparent duplication belongs to renderer visibility: background notices
can start real turns without introducing a rendered human message. Dropping
those events or replies would discard valid conversation, and merging turn
statistics would change their meaning. Keeping the grouping local to the
renderer preserves protocol, transport and per-turn identities.

Use the same rule for live rendering, history and replay so loading older
facts cannot resurrect a superseded row. The boundary is rendered human
input, not a guess based on notification prose.

## Consequence

Consecutive follow-ups no longer leave repeated action rows between replies.
A new rendered human message starts an independent group, preserving the
previous group's footer. Existing item selection and order remain available;
no option, keybinding, protocol field or transport behavior is added.

## Known limitations

Only the latest eligible turn's footer remains directly available in a group;
it does not copy all consecutive replies or report their combined usage or
duration. Existing reply-at-point commands still address earlier text. The
rule uses rendered history and does not fetch missing messages to discover
additional boundaries.
