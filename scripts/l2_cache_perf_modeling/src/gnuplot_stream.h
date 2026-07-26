#pragma once
//
// gnuplot_stream.h
//
// Live Gnuplot dashboard for SystemC simulations.
//

#include <cstdio>
#include <cstdlib>
#include <cstring>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#ifdef _WIN32
#define GP_POPEN  _popen
#define GP_PCLOSE _pclose
#else
#include <signal.h>
#define GP_POPEN  popen
#define GP_PCLOSE pclose
#endif

class GnuplotLive
{
public:

    struct Snapshot
    {
        std::vector<double> cyc;
        std::vector<double> hit_rate;
        std::vector<double> outstanding;
        std::vector<double> cum_completed;
        std::vector<double> latencies;
    };

public:

    explicit GnuplotLive(const std::string& terminal = "");

    ~GnuplotLive();

    bool ok() const
    {
        return alive_;
    }

    void push_snapshot(
        const std::vector<double>& cyc,
        const std::vector<double>& hit_rate,
        const std::vector<double>& outstanding,
        const std::vector<double>& completed,
        const std::vector<double>& latencies);

private:

    bool verify_startup();

    bool write(const std::string& text);

    bool flush();

    bool pipe_good() const;

    void writer_loop();

    void draw(const Snapshot& snap);

    bool send_block(const char* name,
                    const std::vector<double>& x,
                    const std::vector<double>& y,
                    bool is_miss_rate = false);

    bool send_latency_block(const std::vector<double>& lat);

    bool write_xy(const std::vector<double>& x,
                  const std::vector<double>& y,
                  bool is_miss_rate = false);

    bool write_latency(const std::vector<double>& lat);

    bool begin_block(const char* name);

    bool end_block();

    static std::filesystem::path probe_file();

private:

    FILE* pipe_ = nullptr;

    std::thread writer_;

    std::mutex mutex_;

    std::condition_variable cv_;

    Snapshot pending_;

    bool has_pending_ = false;

    std::atomic<bool> running_{false};

    std::atomic<bool> alive_{false};

    std::filesystem::path probe_path_;

    std::ofstream debug_;
};




// Constructor

inline GnuplotLive::GnuplotLive(const std::string& terminal)
{
#ifndef _WIN32
    signal(SIGPIPE, SIG_IGN);
#endif

    debug_.open("gnuplot_debug.txt", std::ios::out | std::ios::trunc);

    // Persist ensures window doesn't close on exit
    pipe_ = GP_POPEN("gnuplot -persist", "w");

    if (!pipe_)
    {
        fprintf(stderr,
                "[GnuplotLive] Failed to launch gnuplot.\n");
        return;
    }

    if (!terminal.empty())
    {
        fprintf(pipe_,
                "set term %s size 1200,850 title 'L2 Cache Performance Monitor'\n",
                terminal.c_str());
        if (debug_)
            debug_ << "set term " << terminal
                   << " size 1200,850 title 'L2 Cache Performance Monitor'\n";
    }

    fprintf(pipe_, "set title 'L2 Cache Performance Monitor'\n");
    fflush(pipe_);

    if (!verify_startup())
    {
        fprintf(stderr,
                "[GnuplotLive] Startup verification failed.\n");

        GP_PCLOSE(pipe_);
        pipe_ = nullptr;
        return;
    }

    alive_ = true;
    running_ = true;

    writer_ = std::thread(&GnuplotLive::writer_loop, this);
}




// Destructor


inline GnuplotLive::~GnuplotLive()
{
    running_ = false;

    cv_.notify_all();

    if (writer_.joinable())
        writer_.join();

    alive_ = false;

    if (pipe_)
    {
        std::fflush(pipe_);
        GP_PCLOSE(pipe_);
        pipe_ = nullptr;
    }
}




// Push latest snapshot

inline void GnuplotLive::push_snapshot(
        const std::vector<double>& cyc,
        const std::vector<double>& hit_rate,
        const std::vector<double>& outstanding,
        const std::vector<double>& completed,
        const std::vector<double>& latencies)
{
    if (!alive_)
        return;

    {
        std::lock_guard<std::mutex> lock(mutex_);

        pending_.cyc = cyc;
        pending_.hit_rate = hit_rate;
        pending_.outstanding = outstanding;
        pending_.cum_completed = completed;
        pending_.latencies = latencies;

        has_pending_ = true;
    }

    cv_.notify_one();
}




// Probe file path


inline std::filesystem::path GnuplotLive::probe_file()
{
    return std::filesystem::temp_directory_path() /
           "gnuplot_live_probe.tmp";
}




// Verify that gnuplot is actually running


inline bool GnuplotLive::verify_startup()
{
    probe_path_ = probe_file();

    fprintf(pipe_, "set print '%s'\n", probe_path_.string().c_str());
    fprintf(pipe_, "print 'alive'\n");
    fprintf(pipe_, "unset print\n");
    fflush(pipe_);
    
    constexpr auto timeout = std::chrono::milliseconds(2000);
    constexpr auto poll = std::chrono::milliseconds(50);
    auto start = std::chrono::steady_clock::now();

    while (std::chrono::steady_clock::now() - start < timeout)
    {
        std::ifstream fin(probe_path_);
        if (fin.good())
        {
            std::string line;
            std::getline(fin, line);
            fin.close();
            std::error_code ec;
            std::filesystem::remove(probe_path_, ec);
            return line == "alive";
        }
        std::this_thread::sleep_for(poll);
    }

    std::error_code ec;
    std::filesystem::remove(probe_path_, ec);
    return false;
}




// Pipe health

inline bool GnuplotLive::pipe_good() const
{
    if (!pipe_) return false;
    return !std::ferror(pipe_);
}




// Safe text writer


inline bool GnuplotLive::write(const std::string& text)
{
    if (!alive_) return false;
    if (!pipe_good())
    {
        alive_ = false;
        return false;
    }
    if (std::fputs(text.c_str(), pipe_) == EOF)
    {
        alive_ = false;
        return false;
    }
    if (debug_) debug_ << text;
    return true;
}



// Flush pipe


inline bool GnuplotLive::flush()
{
    if (!alive_) return false;
    if (std::fflush(pipe_) == EOF)
    {
        alive_ = false;
        return false;
    }
    if (debug_) debug_.flush();
    return true;
}

// Background writer thread

inline void GnuplotLive::writer_loop()
{
    while (true)
    {
        Snapshot snap;

        {
            std::unique_lock<std::mutex> lock(mutex_);
            cv_.wait(lock, [this] { return has_pending_ || !running_; });
            
            if (!running_ && !has_pending_) break;
            
            snap = pending_;
            has_pending_ = false;
        }

        if (!alive_) break;
        
        draw(snap);
        
        if (!alive_) break;

        // Throttle UI updates to max 10 FPS so simulation isn't blocked
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
}

// Begin a gnuplot datablock
inline bool GnuplotLive::begin_block(const char* name)
{
    return write(std::string("$") + name + " << EOD\n");
}

// End datablock
inline bool GnuplotLive::end_block()
{
    return write("EOD\n");
}
// Write X-Y data safely (With Downsampling for Speed)
inline bool GnuplotLive::write_xy(
    const std::vector<double>& x,
    const std::vector<double>& y,
    bool is_miss_rate)
{
    const size_t n = std::min(x.size(), y.size());
    if (n == 0) return true;

    // Downsample massive vectors so gnuplot doesn't lag the simulation
    const size_t MAX_POINTS = 1000;
    size_t step = (n > MAX_POINTS) ? (n / MAX_POINTS) : 1;

    char buffer[128];

    for (size_t i = 0; i < n; i += step)
    {
        double y_val = is_miss_rate ? (100.0 - y[i]) : y[i];
        
        std::snprintf(buffer, sizeof(buffer), "%g %g\n", x[i], y_val);
        if (!write(buffer)) return false;
    }

    // Ensure the very last point is always plotted
    if ((n - 1) % step != 0)
    {
        double y_val = is_miss_rate ? (100.0 - y.back()) : y.back();
        std::snprintf(buffer, sizeof(buffer), "%g %g\n", x.back(), y_val);
        if (!write(buffer)) return false;
    }

    return true;
}




// Write latency vector (With Downsampling for Speed)


inline bool GnuplotLive::write_latency(const std::vector<double>& lat)
{
    if (lat.empty()) return true;

    const size_t MAX_POINTS = 1000;
    size_t step = (lat.size() > MAX_POINTS) ? (lat.size() / MAX_POINTS) : 1;
    char buffer[128];

    for (size_t i = 0; i < lat.size(); i += step)
    {
        std::snprintf(buffer, sizeof(buffer), "%zu %g\n", i, lat[i]);
        if (!write(buffer)) return false;
    }
    
    // Ensure last point is plotted
    if ((lat.size() - 1) % step != 0)
    {
        std::snprintf(buffer, sizeof(buffer), "%zu %g\n", lat.size() - 1, lat.back());
        if (!write(buffer)) return false;
    }

    return true;
}




// Send datablocks

inline bool GnuplotLive::send_block(const char* name,
                                     const std::vector<double>& x,
                                     const std::vector<double>& y,
                                     bool is_miss_rate)
{
    if (!begin_block(name)) return false;
    if (!write_xy(x, y, is_miss_rate)) return false;
    if (!end_block()) return false;
    return true;
}

inline bool GnuplotLive::send_latency_block(const std::vector<double>& lat)
{
    if (!begin_block("latency")) return false;
    if (!write_latency(lat)) return false;
    if (!end_block()) return false;
    return true;
}




// Draw dashboard 


inline void GnuplotLive::draw(const Snapshot& s)
{
    if (!alive_) return;

    // 1. Populate datablocks outside multiplot
    if (!send_block("hitrate", s.cyc, s.hit_rate, false)) return;
    if (!send_block("missrate", s.cyc, s.hit_rate, true)) return;
    if (!send_block("outstanding", s.cyc, s.outstanding)) return;
    if (!send_block("completed", s.cyc, s.cum_completed)) return;
    if (!send_latency_block(s.latencies)) return;

    // 2. Configure multiplot layout using built-in spacing and margins parameters
    // This entirely fixes the overlapping text/graph bug.
    if (!write("set multiplot layout 2,2 title 'L2 Cache Performance Monitor' margins 0.08,0.96,0.10,0.90 spacing 0.12,0.15\n"))
    {
        return;
    }

    // Plot 1 (Top Left): Hit Rate vs Miss Rate
    if (!write("set title 'Hit Rate vs Miss Rate'\n") ||
        !write("set xlabel 'cycle'\n") ||
        !write("set ylabel 'Percentage %'\n") ||
        !write("set yrange [0:100]\n") ||
        !write("set key bottom right\n") ||
        !write(s.cyc.empty() ? "plot NaN notitle\n" : 
               "plot $hitrate with lines lw 2 lc rgb '#3b6fd6' title 'Hit Rate', "
               "$missrate with lines lw 2 lc rgb '#d64545' title 'Miss Rate'\n"))
    {
        write("unset multiplot\n");
        return;
    }

    // Plot 2 (Top Right): Outstanding requests
    if (!write("set title 'Outstanding requests (MSHR proxy)'\n") ||
        !write("set xlabel 'cycle'\n") ||
        !write("set ylabel 'count'\n") ||
        !write("set yrange [*:*]\n") ||
        !write("unset key\n") || 
        !write(s.cyc.empty() ? "plot NaN notitle\n" : "plot $outstanding with lines lw 2 lc rgb '#3b6fd6' notitle\n"))
    {
        write("unset multiplot\n");
        return;
    }

    // Plot 3 (Bottom Left): Completed requests
    if (!write("set title 'Cumulative completed requests'\n") ||
        !write("set xlabel 'cycle'\n") ||
        !write("set ylabel 'count'\n") ||
        !write("set yrange [*:*]\n") ||
        !write("unset key\n") ||
        !write(s.cyc.empty() ? "plot NaN notitle\n" : "plot $completed with lines lw 2 lc rgb '#3b6fd6' notitle\n"))
    {
        write("unset multiplot\n");
        return;
    }

    // Plot 4 (Bottom Right): Latency
    if (!write("set title 'Per-request latency'\n") ||
        !write("set xlabel 'request #'\n") ||
        !write("set ylabel 'cycles'\n") ||
        !write("set yrange [*:*]\n") ||
        !write("unset key\n") ||
        !write(s.latencies.empty() ? "plot NaN notitle\n" : "plot $latency with points pt 7 ps 0.4 lc rgb '#6b45d6' notitle\n"))
    {
        write("unset multiplot\n");
        return;
    }

    // 3. Finish multiplot cleanly
    write("unset multiplot\n");
    flush();
}
