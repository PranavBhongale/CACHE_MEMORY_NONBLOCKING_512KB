

#ifndef MSHR_TABLE_H
#define MSHR_TABLE_H

#include <systemc.h>
#include "../interfaces/L1_interface.cpp"      // l2_if_req_t / l2_if_resp_t, req_op_t, GTAG_W, MSHR_Entry
#include "../interfaces/LLC_interface.cpp"      // l2_llc_req_t / l2_llc_resp_t, LLC_LINE_BITS, LLC_TAG_W
#include "../tag_operation/tag_memory.h"      // TM_INDEX_BITS, TM_TAG_BITS, TM_NUM_WAYS

// Max number of secondary (read-only) waiters an entry can merge while its
// primary fill is outstanding, on top of the primary requester itself.
static const unsigned MSHR_MAX_SEC = 3;

enum mshr_state_t {
    MSHR_IDLE,       // entry free
    MSHR_WB_SEND,    // need to evict a dirty victim first; waiting for LLC port
    MSHR_WB_WAIT,    // writeback request accepted; waiting for WB_ACK from LLC
    MSHR_FILL_SEND,  // ready to request the new line; waiting for LLC port
    MSHR_FILL_WAIT,  // fill request accepted; waiting for RESP_FILL from LLC
    MSHR_COMMIT,     // fill data arrived this cycle; ask global_control to write the arrays
    MSHR_RESP        // draining responses (primary, then secondaries) back to L1
};

struct mshr_entry_t {
    bool         valid;   // entry allocated (in use)
    mshr_state_t state;

    //  identity of the line being installed 
    sc_uint<TM_INDEX_BITS> index;
    sc_uint<TM_TAG_BITS>   line_tag;
    sc_uint<2>              way;        // victim way chosen by SRRIP

    //  eviction (writeback-before-fill) info 
    bool                       need_wb;
    sc_uint<TM_TAG_BITS>       wb_tag;    // victim's OLD tag (for the writeback address)
    sc_biguint<LLC_LINE_BITS>  wb_data;   // victim's OLD data

    //  primary requester (the one that caused the allocation) 
    sc_uint<GTAG_W>            gtag;
    req_op_t                   op;
    bool                       sub_sel;
    sc_biguint<L1_LINE_BITS>   wdata;
    sc_uint<L1_LINE_BYTES>     wmask;

    
    //  secondary (read-only) waiters merged in while this entry is in flight 
    unsigned                   num_sec;
    sc_uint<GTAG_W>            sec_gtag[MSHR_MAX_SEC];
    bool                       sec_sub_sel[MSHR_MAX_SEC];

    //  fill result, latched when RESP_FILL arrives 
    sc_biguint<LLC_LINE_BITS>  fill_data;

    //  response drain cursor: -1 = primary not yet sent, else N secondaries sent 
    int                        resp_next;
};


SC_MODULE(mshr_table) {

    //  Clock / reset 
    sc_in<bool> clk;
    sc_in<bool> rst_n;

    //  Allocate / secondary-merge port (driven by global_control) 
    sc_in<bool>                       alloc_req;          // request an allocation/merge this cycle
    sc_in<sc_uint<TM_INDEX_BITS>>     alloc_index;
    sc_in<sc_uint<TM_TAG_BITS>>       alloc_tag;           // new line's tag
    sc_in<sc_uint<2>>                 alloc_way;           // victim way from SRRIP
    sc_in<bool>                       alloc_victim_dirty;  // victim way was valid && dirty
    sc_in<sc_uint<TM_TAG_BITS>>       alloc_victim_tag;    // victim's old tag (for writeback addr)
    sc_in<sc_biguint<LLC_LINE_BITS>>  alloc_victim_data;   // victim's old data (for writeback)
    sc_in<sc_uint<GTAG_W>>            alloc_gtag;
    sc_in<req_op_t>                   alloc_op;
    sc_in<bool>                       alloc_sub_sel;
    sc_in<sc_biguint<L1_LINE_BITS>>   alloc_wdata;
    sc_in<sc_uint<L1_LINE_BYTES>>     alloc_wmask;

    sc_out<bool> alloc_ready;          // 1 = a free entry exists (safe to allocate this cycle)
    sc_out<bool> alloc_secondary_hit;  // 1 = alloc_req matched an in-flight entry's line and was merged
    sc_out<bool> alloc_full_and_write_conflict; // 1 = alloc_req is a WRITE_BACK that collided with an
    
    //  LLC-facing port (mirrors l2_llc_if's L2-facing side) 
    sc_out<bool>            llc_req_valid;
    sc_out<l2_llc_req_t>    llc_req;
    sc_in<bool>              llc_req_ready;

    sc_in<bool>              llc_resp_valid;
    sc_in<l2_llc_resp_t>     llc_resp;
    sc_out<bool>              llc_resp_ready;

    //  Fill-commit port (tells global_control to write tag_memory + data_array) 
    sc_out<bool>                       commit_valid;
    sc_out<sc_uint<TM_INDEX_BITS>>     commit_index;
    sc_out<sc_uint<2>>                 commit_way;
    sc_out<sc_uint<TM_TAG_BITS>>       commit_tag;
    sc_out<sc_biguint<LLC_LINE_BITS>>  commit_data;
    sc_out<bool>                       commit_dirty;

    //  Upstream response port (mirrors l1_l2_top's L2-facing response INPUT) 
    sc_out<bool>            resp_valid;
    sc_out<l2_if_resp_t>    resp;
    sc_in<bool>              resp_ready;

    //Storage 
    mshr_entry_t entries[MSHR_ENTRIES];

    //  Process 

    void do_mshr();

    void reset_entry(mshr_entry_t &e) {
        e.valid    = false;
        e.state    = MSHR_IDLE;
        e.need_wb  = false;
        e.num_sec  = 0;
        e.resp_next = -1;
    }

    SC_CTOR(mshr_table) {
        for (unsigned i = 0; i < MSHR_ENTRIES; i++)
            reset_entry(entries[i]);

        SC_METHOD(do_mshr);
        sensitive << clk.pos();
        dont_initialize();
    }
};

#endif
