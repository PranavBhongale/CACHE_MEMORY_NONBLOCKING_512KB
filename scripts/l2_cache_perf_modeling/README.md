# L2 Cache Performance Dashboard

A live performance dashboard I built on top of my L2 cache correctness testbench, so I could actually *see* how the cache behaves under load instead of just staring at pass/fail output.

The cache DUT (`l2_cache_top.cpp`) isn't touched at all — the dashboard just watches the same `cpu_*` / `mem_*` ports the testbench already drives, so nothing about the design's timing or behavior changes because I'm watching it.

## What this is

I already had directed correctness tests (fill, hit, write-merge, eviction, secondary-miss merge) for the cache — Tests 1 through 7. What was missing was a way to see how it performs under something closer to real traffic, and to watch that traffic play out live instead of reading a log after the fact.

Test 8 does that: a synthetic workload generator that pushes about 14,500 requests through the cache across six different access patterns, streaming the results into a live 2×2 dashboard as the simulation runs.

## Dashboard

<p align="center">
  <em>(screenshot / gif of the live gnuplot window goes here)</em>
</p>

Four panes, redrawn every 50 cycles:

- **Rolling hit rate** — over the last 200 requests
- **Outstanding requests** — a proxy for MSHR occupancy
- **Cumulative completed requests** — slope tells you throughput
- **Per-request latency** — scatter of cycles vs. request index

To keep the pipe to gnuplot responsive across the full run, the line panes are windowed to the most recent 2,000 samples and the latency scatter to the most recent 3,000 points.

## How hit/miss detection works

There's no internal "hit" wire I can just read — so `PerfMonitor` infers it by correlating the two buses the testbench already watches. If an LLC-side transaction (`mem_req_valid`) shows up for a request's line address before that request gets its response, I count it as a miss; otherwise, a hit. Secondary-miss merges are handled too — if two requests are waiting on the same in-flight line, both get attributed back to the one LLC transaction instead of double-counting. The full reasoning is written up at the top of `perf_monitor.h`.

## Workload phases

The Test 8 traffic generator runs through six phases, each designed to push the cache into a different regime:

| Phase | Pattern | Expected effect |
|---|---|---|
| Warm-up | Small working set, read-heavy | High, stable hit rate |
| Uniform random | Wide working set | More compulsory/capacity misses |
| Hotspot 90/10 | 90% of accesses hit a 4-tag subset | Hit rate climbs |
| Write-heavy | 60% write-back traffic | Stresses dirty-merge/writeback paths |
| Thrashing | 64 tags mapped to 4 indices | Constant eviction, hit rate drops hard |
| Sequential streaming | Always-new addresses | Hit rate near 0%, compulsory misses only |

Up to 15 requests can be in flight at once (4-bit `gtag`, one value reserved for the directed tests), recycled as soon as each response lands.

## Project layout

```
src/
├── perf_monitor.h        # Plain C++ event log — no SystemC dependency
├── gnuplot_stream.h       # Pipes to a persistent gnuplot process
├── tb_l2_cache_top.cpp    # Testbench: Tests 1–7, Test 8, dashboard wiring
├── test_perf_monitor.cpp  # Standalone unit test for perf_monitor.h
└── Makefile
```

## Getting started

You'll need SystemC and gnuplot installed.

```bash
# Sanity-check the perf logic on its own — no SystemC or DUT required
cd src
make test_perf_monitor

# Install gnuplot
sudo apt install gnuplot     # Debian/Ubuntu
brew install gnuplot         # macOS

# Build against SystemC
export SYSTEMC_HOME=/path/to/systemc
make

# Run it — a gnuplot window opens and updates live
make run
```

`tb_l2_cache_top.cpp` includes `../top/l2_cache_top.cpp`, so keep `src/` where it can resolve that relative path.

If your gnuplot build doesn't support the `qt` terminal, switch it in `gnuplot_stream.h`:

```cpp
GnuplotLive plot_{"wxt"};   // or "x11"
```

## A couple of honest caveats

- Hit/miss classification is a heuristic built on bus correlation, not a direct read of ground truth inside the cache — I cross-check the overall hit rate against what each phase should produce rather than trusting it blindly.
- The live plot uses a `popen` pipe to gnuplot, and each redraw blocks briefly on I/O — so simulation pace is coupled to gnuplot's redraw speed. If a run feels sluggish, bump up `PLOT_REFRESH_CYCLES` or trim the phases in `run_perf_workload()`.
