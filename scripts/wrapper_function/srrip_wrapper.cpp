#include <systemc>
#include "../golden_model/SRRIP/srrip_controller_interface.h"
using namespace sc_core;
using namespace sc_dt;

static sc_signal<bool> clk_sig;
static sc_signal<bool> rst_n_sig;

static sc_signal<bool> req_valid_sig;
static sc_signal<sc_uint<INDEX_BITS>> index_sig;
static sc_signal<bool> hit_sig;
static sc_signal<sc_uint<2>> hit_way_sig;      // NOTE: tracks WAY_BITS -- update if NUM_WAYS changes

static sc_signal<sc_uint<2>> victim_way_sig;   // NOTE: same as above
static sc_signal<bool> victim_valid_sig;

static srrip_controller *dut = nullptr;

extern "C"
void rrip_init()
{
    std::cout << "rrip_init()" << std::endl;
    dut = new srrip_controller("SRRIP");
    dut->clk(clk_sig);
    dut->rst_n(rst_n_sig);

    dut->req_valid(req_valid_sig);
    dut->index(index_sig);
    dut->hit(hit_sig);
    dut->hit_way(hit_way_sig);

    dut->victim_way(victim_way_sig);
    dut->victim_valid(victim_valid_sig);

    sc_start(SC_ZERO_TIME);
}

extern "C"
void rrip_clock(int clk)
{
    clk_sig.write(clk);
    sc_start(SC_ZERO_TIME);
}

extern "C"
void rrip_reset(int rst)
{
    rst_n_sig.write(rst ? true : false);
    sc_start(SC_ZERO_TIME);
}

extern "C"
void rrip_drive(
    int req_valid,
    int index,
    int hit,
    int hit_way
)
{
    req_valid_sig.write(req_valid);
    index_sig.write(index);
    hit_sig.write(hit);
    hit_way_sig.write(hit_way);

    sc_start(SC_ZERO_TIME);   // let combinational logic settle on the new inputs
}

// Read outputs back out. Call this AFTER the golden model has been
// clocked for this transaction -- i.e. after rrip_clock() has already
// fired for the posedge that samples the inputs set in rrip_drive().
extern "C"
void rrip_sample(
    int *victim_way,
    int *victim_valid
)
{
    *victim_way   = victim_way_sig.read().to_uint();
    *victim_valid = victim_valid_sig.read();
}

extern "C"
void rrip_finish()
{
    std::cout << "rrip_finish()" << std::endl;
    delete dut;
    dut = nullptr;
}
