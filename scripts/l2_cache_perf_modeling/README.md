# L2 Cache Performance Modeling Environment

A live, real-time performance dashboard built on top of the L2 cache
correctness testbench. The DUT (`l2_cache_top.cpp`) is never modified —
the dashboard only observes the same `cpu_*` / `mem_*` ports the
testbench already drives.

## Overview

- **Tests 1–7**: directed correctness checks (fill, hit, write-merge,
  eviction, secondary-miss merge).
- **Test 8**: a heavy, multi-phase synthetic traffic generator
  (~14,500 requests across 6 phases with different access patterns)
  driving a live 2×2 gnuplot dashboard.
- Hit/miss classification and latency tracking run as pure observers —
  they don't affect DUT timing or behavior.

## Files

| File | Purpose |
|---|---|
| `src/perf_monitor.h` | Plain C++ (no SystemC) event log: classifies each request as hit/miss, tracks latency, MSHR-occupancy proxy, rolling hit rate. |
| `src/gnuplot_stream.h` | Pipes to a persistent `gnuplot` process, redraws a 2×2 live dashboard. |
| `src/tb_l2_cache_top.cpp` | Testbench: Tests 1–7, Test 8 workload, dashboard wiring. |
| `src/test_perf_monitor.cpp` | Standalone unit test for `perf_monitor.h` — no SystemC or DUT needed. |
| `src/Makefile` | Build rules. |

## Dashboard panes

1. **Rolling hit rate (%)** — over the last 200 requests, vs. cycle
2. **Outstanding requests** — a proxy for MSHR occupancy, vs. cycle
3. **Cumulative completed requests** — slope = throughput, vs. cycle
4. **Per-request latency** — scatter, cycles vs. request index

Redraws every 50 cycles (`PLOT_REFRESH_CYCLES`). Line/series panes are
windowed to the most recent 2,000 samples and the latency scatter to the
most recent 3,000 points, keeping the pipe fast over the full 14,500-
request run.

## Hit/miss classification

`PerfMonitor` never reads an internal DUT signal. It correlates the two
buses the testbench already watches: a CPU request is a **miss** if an
LLC-side transaction (`mem_req_valid`) for the same 64B line address is
observed before that request's response arrives; otherwise it's a **hit**.
Secondary-miss merges (two requesters waiting on the same in-flight line)
are handled correctly — both are attributed to the one LLC transaction.
Full detail is documented at the top of `perf_monitor.h`.

## Test 8 workload phases

Defined as a `std::vector<WorkloadPhase>` in `run_perf_workload()`:

1. **Warm-up** — small working set, read-heavy → high, stable hit rate
2. **Uniform random, wide working set** → more compulsory/capacity misses
3. **Hotspot 90/10** — 90% of accesses hit a 4-tag hot subset → hit rate climbs
4. **Write-heavy bursts** — 60% write-back, stresses dirty-merge/writeback paths
5. **Thrashing** — 64 tags over only 4 indices, forcing constant eviction → hit rate drops hard
6. **Sequential streaming** — always-new addresses → hit rate near 0%, compulsory misses only

Each `WorkloadPhase` is `{name, num_requests, num_tags, num_indices,
write_fraction, hotspot_fraction, hotspot_tags, sequential}`.

Up to 15 requests are kept in flight at once (`gtag` is 4 bits wide,
0–15; gtag 0 is reserved for the directed tests), recycled as soon as
each response lands.

## Build & run

Requires SystemC and `gnuplot`.

```bash
# 1. Sanity-check the perf logic on its own (no SystemC/DUT needed)
cd src
make test_perf_monitor

# 2. Install gnuplot
sudo apt install gnuplot        # Debian/Ubuntu
brew install gnuplot            # macOS

# 3. Build against SystemC
export SYSTEMC_HOME=/path/to/systemc
make

# 4. Run — a gnuplot window pops up and updates live
make run
```

`tb_l2_cache_top.cpp` includes `../top/l2_cache_top.cpp` — keep `src/`
adjacent to wherever that path resolves.

If `gnuplot -term qt` isn't supported locally, change the terminal:

```cpp
GnuplotLive plot_{"wxt"};   // or "x11"
```

## Notes

- Hit/miss classification is a bus-correlation heuristic, not a direct
  read of an internal "hit" signal — cross-check the overall hit rate
  against expectations for each workload phase.
- Live-plotting via a `popen` pipe to gnuplot is synchronous: each
  `refresh()` call blocks briefly on I/O, coupling simulation pace to
  gnuplot's redraw speed. Increase `PLOT_REFRESH_CYCLES` if the run
  feels sluggish, or shrink the phases in `run_perf_workload()`.