# Streaming performance audit

The first pass compares the working tree at `f61cef6` **with the already staged
029/030 optimizations** against the additional changes in
[031](../postmortem/031-stream-frontier-and-screen-rows.md). It does not
attribute those earlier batching improvements to this change. The continuation
in [032](../postmortem/032-partial-line-styling-and-burst-follow.md), described
below, uses the completed 031 working tree as its own baseline.
The final-face and pixel-probe pass in
[033](../postmortem/033-final-face-pass-and-pixel-probes.md) starts from 032.
The GUI width-measurement follow-up is recorded in
[034](../postmortem/034-full-table-pixel-widths.md).
The final continuation covers render-scoped font metrics in
[035](../postmortem/035-table-render-metrics.md) and bounded immediate formatting
in [036](../postmortem/036-bounded-stream-markdown.md).

## Path and ownership

| Stage | Current work | Finding |
|---|---|---|
| Transport | WebSocket frame decoding by byte offset; incomplete tail retained; fragments joined at FIN | Existing implementation avoids per-frame tail copying; unchanged in this audit |
| Events | Sequence gate and ordered dispatch | Presentation batching stays downstream; no event dropping or reordering introduced |
| Renderer | Immediate first delta; 50ms reply / 100ms reasoning batches | Already present at the audit baseline; reduces write frequency but cannot alone bound redraw work |
| Markdown | Complete-line scan frontier and unstable-tail formatting | Advancing text-property watermark still modified the stable reply prefix; empty deferred regions still ran formatting passes |
| Viewport | Bottom check and window-start adjustment | Logical line counts disagreed with wrapped screen geometry |
| Other UI | Fragment snapshot comparisons and mode-line caches | Existing local caches remain; no new cache or invalidation policy added |

## Stable text and redraw scope

`dsh-emacs-markdown--set-watermark` previously put a new absolute offset on
the reply's first character after every completed-line flush. Its
`with-silent-modifications` avoids modification hooks and preserves the
modified flag; it does not make changes to buffer properties disappear from
display bookkeeping. Thus incremental regex scanning did not imply that only
the tail was modified.

The stream now owns a `:watermark` marker alongside `:scan` and `:pending`.
Only the newly ready range receives formatting properties. Tests retain the
complete stable prefix, including properties, and assert no subsequent
`put-text-property` calls target its first character. Standalone Markdown
conversion still uses its original serializable property.

This removes a source of broad display invalidation. It is not a measurement
of how many pixels Emacs redraws or a claim that GUI CPU use falls by the same
amount as the removed writes.

## Empty deferred-block work

An unfinished table advances the complete-line scanner but holds the render
frontier at its opening line. Previously each flush still constructed
range collections, invoked inline/block formatting passes and updated the
watermark over an empty ready range. The formatter now returns the empty
range directly, after scanning new lines, with finalization cleanup preserved.

A **fence** is different: since a card's chrome can be written before its body
exists, the opening fence line is rendered as soon as it completes (the card
label and panel lines) and the body then streams raw inside it. Each flush
inside an open block styles only the lines that arrived since the last call —
properties, never text — and no range scan runs at all, so a streamed code
block costs less per flush than the old hold-everything-raw path while never
rewriting text the user has already seen.

## Wrapped viewport reproduction

In an 80-column, 23-row batch window, a 10,000-character line followed by
the input prompt put the anchor at character 10,002. The previous predicate
reported that a window starting at character 1 was at the bottom. Moving
33 screen rows reached only character 2,608. Logical lines also made pinning
choose the start of the entire long paragraph instead of its last screenful.

Both operations now use `vertical-motion` with the target window. Tests
exercise real batch window geometry and verify the input point is preserved.
GUI fonts, pixel scrolling and multiple frame configurations were not timed.

## Measurements

macOS, Emacs 31.1.50, interpreted package code, median of three samples.
Each sample uses a fresh `dsh-emacs-mode` temporary buffer, performs a GC
before timing, and includes GC time. It starts a stream with `intro\n`
(or `intro\n` followed by an opening text fence), then calls
`dsh-emacs-render--start-assistant-stream` and
`dsh-emacs-render--flush-stream` for every delta. A wrapper around
`put-text-property` counts watermark writes before the prior body end.
First-chunk rendering and final highlighting are outside the timed loop.
These intentionally frequent flushes isolate per-refresh cost; they do not
simulate the wall-clock arrival rate of a real model.

| Workload | Before | After |
|---|---:|---:|
| 1,500 `word text\n` deltas | 143 ms | 142 ms |
| First-character watermark writes in that workload | 1,500 | 0 |
| 500 `word text ` deltas, no newlines | 171 ms | 175 ms |
| 1,500 `row\n` deltas inside an unfinished fence | 129 ms | 24 ms |
| GC cycles during the fence loop | 5 | 0 |

The approximately 82% fence-loop reduction comes from removing empty passes.
Ordinary text CPU timings are effectively unchanged; long-paragraph parsing
remained a separate bottleneck for the continuation. A regression test also
confirms that an open fence invokes no source-block parsing pass until its
closing fence arrives.

## Continuation: partial lines and large writes (032)

An `elp` profile of 1,500 plain `word text ` deltas attributed 0.384s to
bold matching and 0.190s to italic matching out of 1.160s inside the Markdown
formatter. The boundary-heavy regexes searched whitespace throughout the
paragraph even though no emphasis delimiters existed. A native delimiter
search now gates these passes and narrows them to one character before the
first delimiter. That retained character preserves the whitespace/BOL rule;
`word*literal*` must not become italic just because scanning starts later.
Other passes continue to see the complete ready range.

Inspecting rich-text properties exposed a second cost: the renderer appended
`dsh-emacs-assistant-body-face` to all ready text on every pass. After twenty
`**bold** text ` deltas, the first bold word had twenty-one copies of that
base face. The renderer now adds it only to runs where it is absent. Reusing
a constant named yank-handler registration also makes a second plain-text
formatting pass preserve `buffer-modified-tick`; paste still strips properties.

The continuation benchmark uses 1,500 deltas per workload, with the same
fresh-buffer / pre-sample GC / per-delta flush method as above. It does not
instrument property writes. Three-sample medians on the same Emacs 31.1.50
environment include GC time and exclude first-chunk and final rendering.
Absolute times across the two passes should not be compared: workloads and
instrumentation differ. These are interpreter batch costs, not GUI frame times.

| Workload | After 031 | After 032 |
|---|---:|---:|
| `word text `, growing plain paragraph | 1.598s | 0.932s |
| `word text\n`, completed lines | 0.176s | 0.153s |
| `**bold** text `, growing rich-text paragraph | 11.204s | 3.917s |
| GC cycles in rich-text workload | 207 | 34 |
| Copies of the base face on the first word after twenty rich-text deltas | 21 | 1 |

The plain and rich-text paragraph costs fall by approximately 42% and 65%.
One thousand deterministic generated inputs retain the 031 formatter's text
and per-character faces, covering whitespace, Chinese, emphasis combinations,
inline code, links, headings and fences. Regression tests also preserve the
left context of an emphasis candidate, plain paste and bounded face lists.

The large-write reproduction starts at the input with a following window,
then writes 100 lines in one operation. The old post-edit bottom check loses
following for first assistant/reasoning chunks, queued text/reasoning flushes,
and corrected final replies. These paths now capture the eligible window list
immediately before editing and pin that list afterward. Tests cover all five
paths, draft preservation, an unselected history reader and a user scroll
between scheduling and flushing. The list is local to the synchronous edit;
it does not lock a window into a persistent follow mode. Hidden buffers skip
the prompt lookup used for following.

## Final face work and pixel probes (033)

The next rich-text profile moved the hotspot to face mirroring: 1.317s of
2.024s inside Markdown for 1,500 deltas. The renderer subsequently traversed
the same runs to add the assistant base face. The order also produced a
concrete inconsistency on completed code: `face` contained the source-block
and assistant faces, while `font-lock-face` contained only the source-block
face.

Markdown's final pass now accepts the renderer's base-face symbol, appends it
only where absent, and mirrors that complete value. Transcript read-only,
stickiness and event properties are then applied in a single call. This
removes a duplicate face traversal and repeated metadata walks, without a new
cache or another render frontier. Standalone conversion defaults to no base
face. Code/table tests compare the final face properties and retain one base
face.

The table pixel probe had a separate correctness problem. Its temporary
insert/delete entered undo history, and a `window-text-pixel-size` error left
the probe string in the destination buffer. Probes now disable undo recording,
clean up through `unwind-protect`, preserve point and markers, and use
`restore-buffer-modified-p` to avoid explicitly refreshing the mode line.
Tests exercise success and a signaled measurement error with both clean and
modified read-only buffers. The pixel-size primitive is controlled in these
tests; they validate cleanup, not real GUI font metrics.

Fresh before/after three-sample medians, using the 032 benchmark method:

| Workload | After 032, remeasured | After 033 |
|---|---:|---:|
| 1,500 `word text ` deltas | 1.032s | 0.832s |
| 1,500 `word text\n` deltas | 0.177s | 0.162s |
| 1,500 `**bold** text ` deltas | 4.210s | 2.720s |
| GC cycles in rich-text workload | 32 | 19 |
| Finalize a 1,000-line Elisp fence | 17ms | 14ms |
| Finalize a 100-row, four-column wrapping table | 111ms | 103ms |

The rich-text loop improves by about 35% in this pass. Absolute results vary
between runs; each table compares its own fresh baseline. The block tests
insert and flush the unfinished source before timing completion, with a GC
before each sample. Code repeats `(message "value %s" (+ 1 2))` on each line.
The table uses the four long cell strings described in 030, with a header and
separator. Finalization includes actual Elisp font-lock and table formatting
in batch, but no GUI redisplay or real pixel probes. Large final blocks remain
synchronous despite the smaller property-processing overhead.

## GUI table width measurement (034)

An isolated graphical Emacs 31.1.50 process exposed a clipping error in the
pixel-width boundary. The default X limit of `window-text-pixel-size` capped
long strings at the window width. With default fonts and text-scale levels
0/2, 500 `W` characters measured 560 pixels in both cases, instead of their
full 3500/5000 pixels. The compatibility path now passes an unlimited X limit.

On Emacs 31 the helper uses `string-pixel-width` with the destination buffer
and temporarily selects the destination window. This public API copies face
remappings into an internal work buffer and avoids edits to the transcript.
Its buffer argument is new in 31; function availability alone is insufficient
on Emacs 29/30. Older versions retain the protected temporary probe.

Real GUI measurements agree between modern and corrected fallback paths for
spaces, Latin text, Chinese, emoji, bold text, variable-pitch text and the long
string above, at both text scales. Three samples of 1000 measurements of
`中文 🙂 **bold**`, with GC before each sample, produced these medians:

| Pixel-measurement path | Elapsed time | Destination character-tick increase |
|---|---:|---:|
| 033 temporary probe | 5.8ms | 8000 |
| Corrected fallback, full width | 6.4ms | 8000 |
| Emacs 31 buffer-aware string measurement | 5.3ms | 0 |

These time differences are small. The primary benefit is eliminating
destination edits during width measurement and correcting clipped widths.
This measures actual GUI font primitives, without timing full redisplay.
The new regressions failed before the fix and pass afterward, asserting full
query bounds, target buffer/window context, restored window selection and
unchanged buffer modification ticks on the modern path.

## Render-scoped font metrics (035)

Height scales were global per character; face-width ratios persisted per
buffer, with no font-change invalidation. Height probes measured a temporary
buffer in the selected window without copying the destination's remapping.
The cache now belongs to one table render, and all pixel paths use the target
window/frame. Emacs 29+ measures height in an undisplayed buffer; the 27.1
fallback preserves the window configuration. ASCII characters in mixed text
skip height probes while variation selectors retain their correction.

An isolated GUI process with default fonts measured these real glyph heights:

| Glyph | Old scale 0 / 2 | New scale 0 / 2 |
|---|---:|---:|
| `A` | 14 / 14 px | 14 / 20 px |
| `中` | 16 / 16 px | 16 / 23 px |
| `🙂` | 20 / 20 px | 20 / 27 px |

The old measurement ignored scaling. Reproduction tests also change metrics
between two renders and assert fresh space/face measurements, correct height
ratios and destination-window selection. Existing rendered tables are not
automatically reflowed by this cache change.

## Bounded immediate formatting and idle preparation (036)

The default `dsh-emacs-stream-markdown-limit` is 8192 pending characters.
Beyond that size, a partial line continues appearing as text but stops being
reparsed on every delta. Its newline/final message makes the region eligible
for full formatting. Large ready regions, including final-only/history replies,
are prepared after 0.1 seconds idle under `while-no-input`. A complete result
is published only if the source character tick still matches. Interruption
retains the visible source and retries later; errors are reported.

The queue retains marker ownership across final-message reconciliation and
new replies. Tests verify that one job cannot absorb the next message, that
publication preserves the next job's bounds, and that reset/death/mode changes
cancel work. `replace-region-contents` keeps positions in matching text where
possible, with a 10ms comparison limit. It receives plain characters; a small
Emacs 31 reproduction showed protected strings could affect a subsequent
coding conversion. Prepared properties are installed separately, including
consistent table-header/base-face precedence.

Fresh three-sample batch medians against the completed 034 tree, using the
same 1500-delta method as 032/033 (GC included, first chunk/finalization excluded):

| Workload | After 034 | After 035/036 |
|---|---:|---:|
| `word text `, growing paragraph | 0.783s | 0.291s |
| `word text\n`, completed lines | 0.160s | 0.151s |
| `**bold** text `, growing rich paragraph | 2.668s | 0.987s |
| GC cycles, rich paragraph | 18 | 10 |

The two long-paragraph loops improve by about 63%. Their display policy is
different: beyond the threshold, new markup waits for a line/final boundary.
Final text and faces are checked separately; this is not a claim that every
delta still receives complete styling immediately.

The GUI completion probe uses an isolated graphical Emacs 31.1.50 process,
default fonts, interpreted package code, three samples and a pre-sample GC.
It inserts an unfinished block, then times closing/final flush plus forced
redisplay. The code fixture has 1000 `(message "value %s" (+ 1 2))` lines; the
table has the same 100 rows/four long cells as 030. The new idle attempt and its
forced redisplay are timed separately, excluding the wait for idle:

| GUI stage | Code | Table |
|---|---:|---:|
| Old final callback, complete styling | 62.9ms | 531.7ms |
| New final callback, raw text visible | 2.6ms | 3.7ms |
| New idle attempt, complete styling and publication | 115.7ms | 557.3ms |

The foreground event is much shorter, but total work can increase because
preparation copies text and publication preserves matching positions and
installs properties. The idle samples include 8/36 GC cycles for code/table.
Preparation is input-interruptible; publication, native calls and GC are not
subject to a hard frame-time bound. Controlled interruption tests validate
discard/retry behavior; this GUI probe did not inject physical keystrokes.
An additional isolated GUI event-loop check used the actual scheduled
callbacks, queued two replies and injected a synthetic `x` input event.
Both replies finished styling, the draft retained `x`, and the pending queue
and timer were empty. The scheduler checks current idle time on 100ms clock
ticks; it does not repeatedly rearm an already elapsed idle deadline.

## Remaining limits and verification scope

- Partial lines below the threshold still rescan; oversized ones postpone new
  styling. Setting the limit to nil restores synchronous repeated processing.
- Idle preparation runs on the main Emacs thread. Input can abort it, but
  publication, native primitives, GC and redisplay can still pause the UI.
  Continuous typing may defer full styling and repeat interrupted work.
- Before Emacs 31, table pixel-width probes still edit the buffer temporarily,
  advancing change ticks and potentially invalidating redisplay. Before Emacs
  29, height probes still briefly display a work buffer. Font metrics are now
  render-scoped; existing tables do not automatically reflow on font/resize.
- Long-line screen motion and actual GUI redisplay still have layout costs.
  Pre-edit capture fixes large live-stream writes. Other event renderers keep
  their existing following paths; the ten-row bottom threshold remains a
  heuristic for identifying eligible windows before an edit.
- Timer deadlines depend on the Emacs event loop. Interleaved event boundaries
  can flush before 50/100ms, and expensive callbacks can delay timers.
- Verification covers syntax, checker self-tests, compilation, the full unit
  suite, silent clean load and repository hygiene. The real-server e2e path
  is unchanged and was not exercised. Emacs 27.1 compatibility is retained
  in the API choices; runtime measurements here use Emacs 31.1.50.

## Continuation: GUI event loop and viewport correction (037)

The live Emacs 31.1.50 investigation found process-triggered redisplay and
competing viewport corrections in addition to Markdown work. Ready chat
sockets now batch reads over 50ms; their received frames retain their order.
The running indicator shares pending text redraws. Native `recenter -1`
accounts for line spacing and the selected draft point when pinning input.
See [037](../postmortem/037-streaming-display-cpu.md) for the decision and
rejected alternatives.

Three alternating before/after runs used the same live GUI configuration,
with profilers stopped and the normal GC threshold. A local TCP producer
sent WebSocket frames with TCP_NODELAY: 100 reasoning deltas, 300 text deltas
and `turn/end`, roughly 10ms apart. Text mixed Chinese, English and bold
markup, with a newline every eighth delta. Each run displayed a fresh chat
buffer and preserved a draft. CPU was measured with `current-cpu-time` over
the whole replay, including redisplay and GC. Before runs used the staged
function definitions; after runs used the final working-tree definitions.

| Measurement | Before | After |
|---|---:|---:|
| CPU / wall time, median | 48.1% | 33.8% |
| Input callbacks, median | 148 | 51 |
| Events received, every run | 401 | 401 |
| Final transcript SHA-256 | Identical | Identical |
| Pending text / busy flag at completion | None | None |

The CPU reduction is about 30% for this workload. Absolute CPU use varies
with frame geometry, fonts, other windows and arrival rate; this is not a
promise that every real reply will use the measured percentage.

A separate GUI reproduction required no new text: follow/redisplay pairs
alternated window start between 794 and 885 with empty input, and between
794 and 911 with a multiline draft. After native recentering, those starts
remained at 885 and 911 respectively. The old character-row calculation
ignored the chat's line spacing and left the cursor offscreen, causing Emacs
to correct scrolling on the next redisplay.

## Render work reports (105)

Run the offline developer probe from a source checkout:

```sh
emacs -Q --batch -l scripts/render-report.el -f dsh-render-report-batch
```

[render-report.el](../scripts/render-report.el) is not loaded by the package.
It uses temporary buffers, makes no RPC requests and installs advice/hooks only
for the duration of each synchronous measurement. Errors propagate after
cleanup. It rejects nested measurements and loaded compiled dsh-emacs modules:
primitive advice cannot reliably observe byte/native-compiled setter calls.
The ordinary standard-library loading policy is unchanged.

Each scenario gets one instrumented work report and five **separate,
uninstrumented** timing samples. Every sample creates and warms a fresh
fixture; setup and a forced GC are excluded, subsequent GC is included. The
540-session fixture has no workspaces or child catalogs and changes only
`Title A` to `Title B` for one session. Fragment fixtures contain 5,000
`body line\n` lines, use minimal styling and are expanded. Hidden buffers use
the renderer's fixed 80-column fallback (76 body columns). The stream cases
flush a real pending plain-text `delta` beside the card **before** measuring
an unchanged card update; they do not time the flush or a Markdown idle job.

`dsh-render-report-measure` accepts a thunk operating on the current buffer
and returns a plist. Its fields have deliberately narrow meanings:

- `:renders`, `:session-rows`, `:stream-flushes` count observed constructors,
  row visits (including children), and flush calls, respectively. All five
  built-in scenarios have zero measured flush calls because their setup is
  outside the report. Generated characters/lines count the fragment result or
  the session source once at the reconciliation boundary, not recursive
  subtree totals. They do not count intermediate allocations.
- `:session-row-builds` counts calls to title padding/truncation during session
  source construction: one per newly built visual row. Cache hits still count
  as `:session-rows` visits, since metadata and descendants must be refreshed.
- `:text-edits` lists chronological `(START OLD NEW)` character-change-hook
  notifications. Coordinates belong to the buffer at each notification;
  this is neither a minimal final diff nor an ETAF edit list to replay.
- `:property-calls` lists setter names, requested intervals and, for
  `put-text-property`, the property name. String writes and writes to other
  buffers are excluded; explicit target-buffer arguments are included.
  Marker endpoints are saved as integer positions when each setter is called,
  so subsequent edits or marker cleanup cannot change the recorded interval.
  Batch output replaces this list with its count and adds `:property-span`,
  the sum of requested interval lengths. Repeated and unchanged writes count
  again. This is **not** unique changed-property coverage or redisplay damage.
- `:text-changed` and `:modified` compare character/general modification ticks.
  `:build-ms` covers fragment construction, or session render entry through
  source preparation. `:other-ms` includes lookup, comparison, reconciliation,
  writes and navigation; it is not pure publication time. Instrumented times
  include advice overhead. Suppressed hooks and deferred timer work are not
  observed; no report measures GUI redisplay.

A local Emacs 31.1.50/macOS source run based on `e8cf554` plus the working-tree
changes, **before visual row reuse (106)**, produced the following results.
These are synthetic batch samples, separate from the historical streaming and
GUI results above.

| Scenario | Rebuild work | Character notifications | Property calls / summed span | Uninstrumented median (range), ms |
|---|---|---|---:|---:|
| One session title | 540 row visits; 29,241 source chars | One 54→54 row replacement | 3,246 / 29,241 | 12.462 (11.978–13.539) |
| Expanded fragment title | One build; 50,009 chars | Delete one char, insert one char | 1 / 50,009 | 2.712 (2.612–4.120) |
| Warm unchanged fragment | None | None | 0 / 0 | 0.032 (0.028–0.041) |
| Unchanged fragment after nearby stream | One build; 50,009 chars | None | 0 / 0 | 1.678 (1.604–1.982) |
| Same fragment, warmed again | None | None | 0 / 0 | 0.030 (0.027–0.038) |

The title-only fragment update still writes its authoritative full-block state
property; it does not restyle the unchanged body. Nearby stream writes still
invalidate the conservative whole-buffer cache tick. This trades a subsequent
reconstruction for correctness when external code edits a fragment.

A discarded session-property experiment compared both source and target
property boundaries and skipped intervals whose values were all `eq`, keeping
fresh mutable metadata objects. Setter requests fell from 3,246 to 545 and
summed spans from 29,241 to 591, but one five-sample trial had a 17.251 ms median
versus 10.595 ms for the preceding baseline. Later baseline samples also varied;
these observations do not establish a general speed ratio. They showed no
reason to retain the extra comparisons, so property publication remains unchanged.
A comparison of only each source run's first character would also miss stale
metadata inside that run and is not a valid alternative.

Tests cover target-buffer scoping, hook locality, exception cleanup, unchanged
cache behavior and equality of ordinary/instrumented output including text
properties. Millisecond thresholds are not test assertions. The script is in
the normal syntax gate; see [105](../postmortem/105-render-work-reports.md) for
the decision to adopt diagnostics rather than a retained-tree renderer.

## Session visual row reuse (106)

Each session-list buffer retains the visual strings for rows emitted by its
last successful publication. A row is rebuilt when its resolved title (including
text properties), status, indentation, disclosure glyph or rendered detail
changes. Title snapshots detect in-place mutation of protocol strings; relative
time is recomputed on every visit, so an unchanged timestamp can age into a new
bucket. Child mode and activity are part of the rendered detail.

This cache saves title width/truncation, padding and styled-string construction.
It does not cache command targets: every visit attaches the current session,
workspace and direct-parent/catalog-entry metadata, then traverses descendants
and renders loading/error notices. Target-buffer edits are still repaired by
row reconciliation and full property publication. After publication, the new
cache replaces the old one, pruning folded, removed and filtered rows. Another
list buffer starts with its own empty cache.

In the 540-session title-change fixture, row visits remain **540**, while actual
visual row builds fall from **540 to 1**; a fully unchanged refresh builds none.
The full source still has 545 lines / 29,241 characters, one 54→54 character
replacement, and 3,246 property requests covering 29,241 summed characters.
Neither source generation nor publication becomes proportional to changed rows.

For a separate latency comparison, byte-compile the complete baseline and
cached session modules into temporary directories, with all other compiled
production modules held constant. Load the selected full module outside each
timed sample; alternate baseline/cache order within each pair. Use a fresh
hidden buffer and 540 fresh sessions for each sample, discard two warmup pairs,
and keep all 16 measured pairs. Force GC before timing the full render and
include any GC during it. Cold means an empty destination/cache, not a cold
Emacs process; warm means one initial render followed by one changed title.

The ASCII fixture uses 11-column titles. The CJK/mixed fixture uses five
repeated development-task titles, 37–44 characters / 67–69 columns, which need
46-column truncation. Sessions use a shared numeric Unix-millisecond timestamp
about two hours old. There are no workspaces or children in this timing fixture;
those paths have separate regression coverage. Batch measurements omit GUI
redisplay, network traffic, mode hooks and long-lived allocation/GC effects.

On Emacs 31.1.50 / macOS arm64, the corrected timestamp fixture produced:

| 540-row case | Baseline median ms | Cached median ms | Paired savings median ms | Paired savings median % |
| --- | ---: | ---: | ---: | ---: |
| ASCII, cold | 5.763 | 5.817 | 0.082 | 1.384% |
| ASCII, one-title update | 6.503 | 5.954 | 0.613 | 9.496% |
| CJK/mixed, cold | 6.866 | 6.616 | -0.033 | -0.512% |
| CJK/mixed, one-title update | 7.532 | 6.109 | 1.281 | 16.731% |

Paired savings are computed for each baseline/cache pair before taking the
median; they are not the difference or ratio of the two independent medians.
Positive savings mean faster cached rendering. Warm ASCII improved in 13/16
pairs, and warm CJK in 15/16. Warm paired savings IQRs were 0.202–1.480 ms and
0.787–1.649 ms respectively. The CJK cache timings included a 10.073 ms outlier;
all samples were retained. Both cold paired IQRs cross zero, so this run does
not resolve a consistent cold-start gain or penalty. No timed render triggered
GC, and output including properties matched for all four fixture variants.
These batch results support retaining the cache for repeated updates,
especially truncating titles; they do not establish a GUI latency guarantee.

Regression coverage includes in-place title mutation, property-only title
changes, status and time buckets, fallback titles, replacement metadata,
workspace renaming, child mode/activity, new grandchildren, error notices,
fold/removal pruning, buffer isolation, failed publication and repair of external
text/property edits. Existing regrouping and per-window focus tests still run.
See [106](../postmortem/106-session-row-cache.md) for the decision and measurement
limits.
