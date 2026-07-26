# L2 Cache Golden Model — MSHR, Global Control, and Top Integration

This documents what was added to your golden model, what had to be fixed
in the existing files to make everything connect correctly, and how the
result was verified.

## 1. What was added

### `MSHR_CONTROL_AND_TABLES/mshr_table_interface.cpp` + `mshr_table.cpp`
An 8-entry MSHR (matches `MSHR_ENTRIES` / `L2_MSHR_ENTRIES` = 8, already
fixed at that size on both the L1 and LLC interfaces). Each entry tracks:
- the line being installed (index, tag, victim way),
- whether the victim needs writing back first (valid && dirty), and its
  old tag/data,
- the primary requester (gtag, op, sub_sel, write data/mask), and
- up to 3 secondary **read** requesters merged into the same in-flight
  entry (secondary-miss merging).

Per-entry state machine: `IDLE → [WB_SEND → WB_WAIT] → FILL_SEND →
FILL_WAIT → COMMIT → RESP → (freed)`. The writeback and fill are two
sequential LLC transactions reusing the entry's own index as the LLC tag
(per the existing "L2's own MSHR index is reused directly as the
transaction tag" design in `LLC_interface.cpp`). Secondary-miss merging
is deliberately **read-only**: a writeback that collides with an
in-flight entry is reported back to `global_control` as a conflict and
retried later, rather than racing two writers into the same not-yet-
committed fill buffer.

### `GLOBAL_CONTROL/global_control_interface.cpp` + `global_control.cpp`
The pipeline sequencer that was missing between your existing modules.
It implements the standard tag-access / tag-compare pipeline you
described, using `tag_memory` for tag access and `tag_compare` for the
compare stage, then:
- **hit** → read (and, for an L1 writeback, merge + write back) the
  matching way in `data_array`, respond.
- **miss** → ask `srrip_controller` for a victim, read that way out of
  `data_array` to see if it needs writing back, hand everything to
  `mshr_table`.

It also performs the actual `tag_memory` / `data_array` writes when
`mshr_table` reports a completed fill, and arbitrates the shared
L1-facing response port between its own hit responses and `mshr_table`'s
completed-fill responses (fills win; a hit response that loses simply
retries next cycle rather than being dropped).

It processes one request through the front end at a time rather than
accepting a new one every cycle — see the comment block at the top of
`global_control_interface.cpp` for why, and why the actual non-blocking
behavior (many misses resolving concurrently against the LLC) still
holds regardless.

### `top/l2_cache_top.cpp`
Instantiates and wires `tag_memory`, `tag_compare`, `srrip_controller`,
`data_array`, `mshr_table`, and `global_control` together. Its ports are
shaped to plug directly into the existing glue modules one level out:
`cpu_*` mirrors `l1_l2_top`'s L2-facing port, `mem_*` mirrors `l2_llc_if`'s
L2-facing port. It does **not** itself instantiate `l1_l2_arbiter` /
`l1_l2_top` or `l2_llc_if` — those already exist and belong in a
higher-level system top, one level further out from the L2 itself.

## 2. Bugs fixed in the existing files

These were required to make the pieces connect at all; each is called
out in the affected file with an `INTEGRATION FIX` comment.

1. **`interfaces/LLC_interface.cpp` — `ADDR_W`/`TAG_W` name collision.**
   Both this file and `L1_interface.cpp` declared identically-named
   global constants. Harmless in isolation, but the L2 top needs both
   headers in the same translation unit (it drives an L1-facing port and
   an LLC-facing port at once), which fails to compile as a redefinition.
   Renamed to `LLC_ADDR_W` / `LLC_TAG_W` (values unchanged) and added a
   missing include guard.

2. **`tag_operation/tag_memory.cpp` — 32-bit address assumption.**
   `TM_ADDR_BITS` was a placeholder `32` ("ASSUMPTION: change if
   needed"). Both `L1_interface.cpp` and `LLC_interface.cpp` carry a
   64-bit address. Fixed to `64`, which recomputes `TM_TAG_BITS` to 47.

3. **`tag_compare/tag_compare_top.cpp` — matching tag width.**
   `TC_TAG_BITS` was hardcoded to `15` (matching tag_memory's old 32-bit
   assumption, with a "keep in sync with TM_TAG_BITS" comment). Updated
   to `47` to match fix #2.

4. **`data_array/data_array.cpp` — geometry mismatch.**
   This file used 1024 sets × 8 ways (10-bit index, 3-bit way), while
   `tag_memory.cpp` and `srrip_controller.cpp` both already agreed on
   2048 sets × 4 ways (11-bit index, 2-bit way). Same total capacity
   (512KB) either way, but a shared index/way pair from the tag-compare
   / replacement stage has to address all three arrays consistently.
   Realigned `data_array` to 2048×4 to match the other two.

None of these change any module's external behavior for the geometry it
already assumed — they just make the three already-mutually-inconsistent
assumptions agree with each other.

## 3. Verification

`verification/tb_l2_cache_top.cpp` is a self-checking SystemC testbench:
`l2_cache_top` on one side, a small LLC memory stub (fixed 2-cycle
latency, backed by an address→line map) on the other. It exercises:

1. Read miss → fill (data matches the LLC's fill pattern).
2. Re-read the same line → hit (no LLC traffic, same data).
3. Write-back hit → merges only the masked bytes, sets dirty.
4. Re-read → confirms only the written byte changed, rest of the line
   intact (proves the merge doesn't clobber the rest of the line).
5. Three more distinct tags filled into the same set (associativity).
6. A 5th distinct tag forces an eviction. All four resident lines are
   first dirtied via write-back hits so the SRRIP-selected victim is
   guaranteed dirty; verifies a writeback transaction reaches the LLC
   *before* the fill for the new line, and that a dirty writeback
   actually happens.
7. Two read misses to the same brand-new line, issued back-to-back:
   verifies the second is merged as a secondary MSHR waiter (not a
   second LLC transaction) and both requesters get the freshly-filled
   data.

**Result: all 15 checks pass** (`0 failing check(s)`), run under the
actual SystemC 2.3.4 kernel — not just compiled, but simulated.

### Bugs the testbench actually caught and fixed along the way
- `global_control`: the two "waiting for a registered module to settle"
  states (`GC_TAG_WAIT`, `GC_VICTIM_WAIT`) never advanced to the next
  state — the pipeline hung forever on the very first miss.
- `global_control`: SRRIP was only ever driven on the miss path, so
  RRPV promotion on a hit never happened (would have degraded the
  replacement policy over time without ever showing up as a hard
  failure).
- `mshr_table`: the response-drain logic gated computing `resp_valid`
  on `resp_ready` already being true — a genuine deadlock (valid never
  rises because ready never rises because valid never rises), which
  also permanently leaked the MSHR entry.
- `mshr_table`: an off-by-one in the "all responses drained, free this
  entry" check meant an entry with any secondary waiters was never
  freed after its last secondary was served, silently leaking that
  entry for the rest of the simulation.

## 4. Known limitations / scope notes

- The front end serializes one request at a time through tag access →
  compare → victim/allocate (see the note in
  `global_control_interface.cpp`). Multiple misses can still be
  in flight concurrently once handed to the MSHR; only the front-end
  decision-making itself isn't deeply pipelined.
- Secondary-miss merging only applies to reads, by design (see the
  `mshr_table_interface.cpp` header comment).
- `l2_req_ready` is a registered (not combinational) signal, standard
  for this codebase's style: an external requester should hold its
  request stable until it observes `ready`, and should expect roughly
  one more cycle before presenting a *different* request — see the
  driver loop in `tb_l2_cache_top.cpp`'s `send_req()` for a correct
  reference implementation of that contract.
- This model does not implement multi-core coherence / snooping — the
  LLC interface already stubs that out as a documented future extension
  point, unchanged here.
