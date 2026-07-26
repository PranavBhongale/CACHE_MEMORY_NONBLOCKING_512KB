#pragma once
// perf_monitor.h
//
// PerfMonitor is plain C++ (no SystemC types) so it can be unit-tested and
// reasoned about outside the simulation. It is fed entirely by the
// testbench's own port reads (cpu_req/cpu_resp/mem_req) — it never touches
// l2_cache_top's internals, so it stays valid even if the DUT changes.
//
// Hit/miss classification heuristic:
//   A CPU-side request is classified MISS if, before its response arrives,
//   at least one LLC-side transaction (mem_req_valid) is observed for the
//   same 64B line address. Otherwise it's a HIT. Multiple CPU requests
//   waiting on the same in-flight line (secondary-miss merge, see Test 7
//   in the original testbench) are all correctly attributed to that one
//   LLC transaction.
//   This is a black-box heuristic based only on the two buses the
//   testbench already has visibility into. If l2_cache_top ever exposes an
//   explicit "this access hit" signal, prefer wiring that directly into
//   on_resp() instead — it would be more precise than bus correlation.

#include <cstdint>
#include <vector>
#include <deque>
#include <unordered_map>
#include <algorithm>

class PerfMonitor {
public:
    static constexpr int ROLLING_WINDOW = 200;   // requests, for hit-rate smoothing
    static constexpr int SAMPLE_EVERY_N_CYCLES = 10;

    // Call once per posedge clk (after reset deasserts).
    void begin_cycle(uint64_t cycle) {
        cur_cycle_ = cycle;
        maybe_sample();
    }

    // Call right after a CPU request's handshake completes (req accepted).
    void on_req_issued(unsigned gtag, uint64_t line_addr) {
        outstanding_[gtag] = Outstanding{line_addr, cur_cycle_, false};
        pending_by_line_[line_addr].push_back(gtag);
    }

    // Call whenever mem_req_valid fires, with the LLC-side request's line addr.
    void on_llc_req(uint64_t line_addr) {
        auto it = pending_by_line_.find(line_addr);
        if (it == pending_by_line_.end()) return;
        for (unsigned g : it->second) {
            auto oit = outstanding_.find(g);
            if (oit != outstanding_.end()) oit->second.went_to_llc = true;
        }
    }

    // Call whenever cpu_resp_valid fires, with that response's gtag.
    void on_resp(unsigned gtag) {
        auto it = outstanding_.find(gtag);
        if (it == outstanding_.end()) return;  // unknown gtag, ignore defensively

        const bool hit = !it->second.went_to_llc;
        const uint64_t latency = cur_cycle_ - it->second.issue_cycle;

        completed_total_++;
        if (hit) hits_total_++; else misses_total_++;

        recent_outcomes_.push_back(hit);
        if ((int)recent_outcomes_.size() > ROLLING_WINDOW) recent_outcomes_.pop_front();

        latency_series_.push_back((double)latency);

        auto lit = pending_by_line_.find(it->second.line_addr);
        if (lit != pending_by_line_.end()) {
            auto &vec = lit->second;
            vec.erase(std::remove(vec.begin(), vec.end(), gtag), vec.end());
            if (vec.empty()) pending_by_line_.erase(lit);
        }
        outstanding_.erase(it);
    }

    // ---- snapshot series for plotting (read-only, safe to call anytime) ----
    const std::vector<double>& cycle_axis()           const { return cycle_axis_; }
    const std::vector<double>& hit_rate_series()       const { return hit_rate_series_; }
    const std::vector<double>& outstanding_series()    const { return outstanding_series_; }
    const std::vector<double>& cum_completed_series()  const { return cum_completed_series_; }
    const std::vector<double>& latency_series()        const { return latency_series_; }

    uint64_t completed_total() const { return completed_total_; }
    uint64_t hits_total()      const { return hits_total_; }
    uint64_t misses_total()    const { return misses_total_; }
    size_t   outstanding_count() const { return outstanding_.size(); }

private:
    struct Outstanding { uint64_t line_addr; uint64_t issue_cycle; bool went_to_llc; };

    void maybe_sample() {
        if (SAMPLE_EVERY_N_CYCLES <= 0 || cur_cycle_ % SAMPLE_EVERY_N_CYCLES != 0) return;
        double hr = 0.0;
        if (!recent_outcomes_.empty()) {
            long hits = std::count(recent_outcomes_.begin(), recent_outcomes_.end(), true);
            hr = 100.0 * (double)hits / (double)recent_outcomes_.size();
        }
        cycle_axis_.push_back((double)cur_cycle_);
        hit_rate_series_.push_back(hr);
        outstanding_series_.push_back((double)outstanding_.size());
        cum_completed_series_.push_back((double)completed_total_);
    }

    uint64_t cur_cycle_ = 0;
    uint64_t completed_total_ = 0, hits_total_ = 0, misses_total_ = 0;

    std::deque<bool> recent_outcomes_;
    std::unordered_map<unsigned, Outstanding> outstanding_;
    std::unordered_map<uint64_t, std::vector<unsigned>> pending_by_line_;

    std::vector<double> cycle_axis_, hit_rate_series_, outstanding_series_, cum_completed_series_;
    std::vector<double> latency_series_;
};
