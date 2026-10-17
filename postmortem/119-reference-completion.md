# 119 - Responsive reference discovery and matching

## Background

Against `bedd3b2`, the reference completion layer still made two synchronous
requests on a cold cache. Its asynchronous path initialized both slices to
nil, then used `listp` to decide whether both replies had arrived: the first
reply could therefore finish the request. Corfu retained a frozen completion
table while newer host results accumulated elsewhere.

Filtering compounded this. A display-only `flex` pass could reject a valid
host match by filename case, session ID/workspace, or the opening quote of a
path. Empty-string enumeration tests missed this because they never exercised
native matching with the actual token. Stock completion's ambiguous `exact`
status also finalized chips before the user had accepted a candidate.

## Decision

Keep ownership in `dsh-emacs-reference.el`: one debounced asynchronous request
path for every frontend, pending/failed/settled response states, and generation
invalidation after a pick. Warm Corfu as well as other frontends. A live table
refreshes its presentation snapshot when the cache changes; insertion resolves
against that snapshot, not against an unrelated later reply.

Use a category-specific completion style (`dsh-emacs-reference-search`, named
distinctly from the category so a `(styles ...)` override reads
unambiguously) to preserve fresh host matches. While loading, case-insensitive subsequence matching searches cached
paths, labels, IDs and directories separately from mention syntax. A dedicated
table action keeps ordinary user-selected completion styles working normally.
Explicit path quotes survive insertion, and only `finished`/`sole` statuses
finalize chips. Index icon metadata once rather than scanning the full cache
for each row.

## Why

Shorter timers cannot fix blocking requests, incorrect settlement, or a frozen
candidate universe. Reimplementing workspace discovery locally would disagree
with remote servers and duplicate the host's ranking. Filtering only visible
labels cannot reproduce a host search over hidden session fields.

The prior policy of never touching an active Corfu popup was compensating for
snapshot tables rather than providing live results. Refresh the live table
through guarded native recomputation instead of repeatedly quitting/reopening
completion or invoking generic CAPF insertion from a network callback.

## Consequence

Cold completion returns immediately, query changes coalesce, and fresh results
reach the popup. TAB-only frontends and the explicit menu may need a second
invocation when the first discovery is still loading. The original wire
mentions, files/directories/sessions grouping and user category overrides stay
intact. Record 010's synchronous-first-fetch decision is superseded; its grammar
and host-side snapshot responsibilities are unchanged.

Regression tests exercise native completion styles and stock acceptance, real
callback ordering, stale generations, timer cancellation, quoted drilling,
foreign-buffer table calls, host-authoritative fresh results, prefetch on every
frontend, and picks after cache replacement. An isolated GUI run with installed
Corfu and mocked RPCs confirmed cold popup opening, case-insensitive filtering,
query coalescing and nested results arriving in the active popup without
changing the draft.

A synthetic 5,000-file icon snapshot on Emacs 31.1.50 took about 124 ms per pass
before and 3.6 ms after (three passes, no timed GCs). This measures local table
work, not server discovery or end-to-end interactive latency.

## Known limitations

Server discovery still takes time and may return only a ranked subset. Cached
fallbacks cannot find entries absent from that subset until the host responds.
As before, a partial endpoint failure keeps the successful slice for that
query; retrying the failed slice requires changing the query or starting a new
reference. Failures are now reported rather than silently hidden. Non-Corfu
frontends refresh on their next completion rather than gaining a new auto-popup
mechanism. The explicit `M-x dsh-emacs-reference` menu deliberately has no
blocking cold path either: with no cache it reports loading and must be invoked
again, accepting a second invocation so that every discovery path is
non-blocking. Corfu's guarded private refresh entry points remain an
integration seam to recheck when upgrading the frontend. GUI perception such
as flicker was not measured by the automated state probe.
