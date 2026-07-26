// Standalone sanity test for perf_monitor.h - no SystemC dependency.
// Build: g++ -std=c++17 test_perf_monitor.cpp -o test_perf_monitor
#include "perf_monitor.h"
#include <cassert>
#include <iostream>

int main() {
    PerfMonitor pm;

    // Cycle 0..9: request gtag=1 to line 0x1000 issued at cycle 1, goes to LLC
    // (miss), resolves at cycle 5.
    for (uint64_t c = 0; c <= 5; c++) {
        pm.begin_cycle(c);
        if (c == 1) pm.on_req_issued(1, 0x1000);
        if (c == 2) pm.on_llc_req(0x1000);       // this one misses
        if (c == 5) pm.on_resp(1);
    }
    assert(pm.completed_total() == 1);
    assert(pm.hits_total() == 0);
    assert(pm.misses_total() == 1);
    assert(!pm.latency_series().empty());
    assert(pm.latency_series().back() == 4.0); // 5 - 1

    // Cycle 10: request gtag=2 to line 0x2000, resolves at cycle 12 with NO
    // llc_req in between -> hit.
    for (uint64_t c = 10; c <= 12; c++) {
        pm.begin_cycle(c);
        if (c == 10) pm.on_req_issued(2, 0x2000);
        if (c == 12) pm.on_resp(2);
    }
    assert(pm.completed_total() == 2);
    assert(pm.hits_total() == 1);
    assert(pm.misses_total() == 1);

    // Secondary-miss merge: two gtags (3,4) both waiting on line 0x3000; a
    // single llc_req should mark BOTH as misses.
    pm.begin_cycle(20);
    pm.on_req_issued(3, 0x3000);
    pm.on_req_issued(4, 0x3000);
    pm.begin_cycle(21);
    pm.on_llc_req(0x3000);
    pm.begin_cycle(25);
    pm.on_resp(3);
    pm.on_resp(4);
    assert(pm.misses_total() == 3); // previous 1 + these 2
    assert(pm.completed_total() == 4);
    assert(pm.outstanding_count() == 0);

    // Sampling should have produced some series points by now (cycle 20 is
    // a multiple of SAMPLE_EVERY_N_CYCLES=10).
    assert(!pm.cycle_axis().empty());
    assert(pm.cycle_axis().size() == pm.hit_rate_series().size());
    assert(pm.cycle_axis().size() == pm.outstanding_series().size());
    assert(pm.cycle_axis().size() == pm.cum_completed_series().size());

    std::cout << "All PerfMonitor checks passed. "
              << "completed=" << pm.completed_total()
              << " hits=" << pm.hits_total()
              << " misses=" << pm.misses_total()
              << " samples=" << pm.cycle_axis().size() << std::endl;
    return 0;
}
