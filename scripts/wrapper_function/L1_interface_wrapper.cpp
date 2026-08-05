#include <systemc>
#include "../golden_model/interfaces/L1_L2_TOP_INTERFACE.CPP"
using namespace sc_core;
using namespace sc_dt;

/// clk and reset signals for the top-level module
static sc_signal<bool> clk_sig;
static sc_signal<bool> rst_n_sig;

// L1 I client port (pass-through to the arbiter)

static sc_signal<l2_req_t>   i_req_sig;
static sc_signal<bool>      i_req_ready_sig;
static sc_signal<l2_resp_t> i_resp_sig;
static sc_signal<bool>       i_resp_ready_sig;

// L1 D client port (pass-through to the arbiter)
static sc_signal<l2_req_t>   d_req_sig;
static sc_signal<bool>      d_req_ready_sig;
static sc_signal<l2_resp_t> d_resp_sig;
static sc_signal<bool>       d_resp_ready_sig;

// l2 facing port: this is the buffered interface to L2
static sc_signal<bool>         l2_req_valid_sig;
static sc_signal<l2_if_req_t>  l2_req_sig;  
static sc_signal<bool>          l2_req_ready_sig;
static sc_signal<bool>          l2_resp_valid_sig;

static sc_signal<l2_if_resp_t>  l2_resp_sig;
static sc_signal<bool>         l2_resp_ready_sig;

extern "C"
void l1_l2_top_init()
{
    std::cout << "l1_l2_top_init()" << std::endl;
    l1_l2_top<MSHR_ENTRIES, MSHR_ENTRIES> *dut = new l1_l2_top<MSHR_ENTRIES, MSHR_ENTRIES>("L1_L2_TOP");
    dut->clk(clk_sig);
    dut->rst_n(rst_n_sig);

    dut->i_req(i_req_sig);
    dut->i_req_ready(i_req_ready_sig);
    dut->i_resp(i_resp_sig);
    dut->i_resp_ready(i_resp_ready_sig);

    dut->d_req(d_req_sig);
    dut->d_req_ready(d_req_ready_sig);
    dut->d_resp(d_resp_sig);
    dut->d_resp_ready(d_resp_ready_sig);

    dut->l2_req_valid(l2_req_valid_sig);
    dut->l2_req(l2_req_sig);
    dut->l2_req_ready(l2_req_ready_sig);

    dut->l2_resp_valid(l2_resp_valid_sig);
    dut->l2_resp(l2_resp_sig);
    dut->l2_resp_ready(l2_resp_ready_sig);
}

extern "C"
void l1_l2_top_clock(int clk)
{
    clk_sig.write(clk);
    sc_start(SC_ZERO_TIME);
    cout << "l1_l2_top_clock() clk=" << clk << "clock is getting triggered" << std::endl;
}

extern "C"
void l1_l2_top_reset(int rst)
{
    rst_n_sig.write(rst ? true : false);
    sc_start(SC_ZERO_TIME);
    cout << "l1_l2_top_reset() rst=" << rst << "reset is getting triggered" << std::endl;
}

extern "C"
 void l1_l2_top_drive(
   l2_req_t i_req,
   bool i_req_ready,
    l2_resp_t i_resp,
    bool i_resp_ready,
    l2_req_t d_req,
    bool d_req_ready,
    l2_resp_t d_resp,
    bool d_resp_ready,
     
     // l2 facing port: this is the buffered interface to L2
        l2_if_req_t l2_req,
        bool l2_req_valid,
        bool l2_req_ready,

        l2_if_resp_t l2_resp,
        bool l2_resp_valid,
        bool l2_resp_ready
 )
 {
    // here is the connection between the wrapper and the top-level module
    i_req_sig.write(i_req);
    i_req_ready_sig.write(i_req_ready);
    i_resp_sig.write(i_resp);
    i_resp_ready_sig.write(i_resp_ready);
    d_req_sig.write(d_req);
    d_req_ready_sig.write(d_req_ready);
    d_resp_sig.write(d_resp);
    d_resp_ready_sig.write(d_resp_ready);


    // request from L1 to L2
    l2_req_sig.write(l2_req);
    l2_req_valid_sig.write(l2_req_valid);
    l2_req_ready_sig.write(l2_req_ready);

    // response from L2 to L1
    l2_resp_sig.write(l2_resp);
    l2_resp_ready_sig.write(l2_resp_ready);
    l2_resp_valid_sig.write(l2_resp_valid);
 }

 