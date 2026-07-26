//
//
#ifndef GLOBAL_CONTROL_H
#define GLOBAL_CONTROL_H

#include <systemc.h>
#include "../interfaces/L1_interface.cpp"
#include "../tag_operation/tag_memory.h"
#include "../tag_compare/tag_compare_top.h"
#include "../SRRIP/srrip_controller_interface.h"
#include "../data_array/data_array.cpp"

enum gc_state_t {
    GC_IDLE,          // waiting for / accepting a new request
    GC_TAG_WAIT,      // tag_memory is capturing the index this edge
    GC_COMPARE,       // tag_compare's hit/miss/hit_way are now valid
    GC_DATA,          // (hit) data_array's read of hit_way is now valid
    GC_RESPOND,        // (hit) driving the response, arbitrating vs. mshr
    GC_VICTIM_WAIT,   // (miss) srrip_controller is capturing this edge
    GC_VICTIM,        // (miss) victim_way/victim_valid now valid
    GC_VICTIM_DATA,   // (miss) data_array's read of the victim way is valid
    GC_ALLOC_WAIT,    // (miss) mshr_table is capturing alloc_req this edge
    GC_ALLOC_CHECK    // (miss) alloc_ready/secondary_hit/conflict now valid
};

struct gc_request_t {
    bool                    valid;
    l2_if_req_t             req;
    sc_uint<TM_INDEX_BITS>  index;
    sc_uint<TM_TAG_BITS>    tag;

    bool                    hit;
    sc_uint<2>               hit_way;
    sc_uint<TM_TAG_BITS>    way_tag[NUM_WAYS];
    sc_uint<NUM_WAYS>        way_valid_bits;

    sc_uint<2>               victim_way;
    bool                     victim_valid;
    bool                     need_wb;
    sc_uint<TM_TAG_BITS>     victim_tag;
    sc_biguint<LINE_BITS>    victim_data;

    sc_biguint<LINE_BITS>    line_data;   // hit-path read result (merged, if a writeback hit)
};

SC_MODULE(global_control) {

    //  Clock / reset 
    sc_in<bool> clk;
    sc_in<bool> rst_n;

    //  Upstream (L1-facing) port 
    // Mirrors l1_l2_top's L2-facing ports exactly (see L1_L2_TOP_INTERFACE.CPP)
    sc_in<bool>            l2_req_valid;
    sc_in<l2_if_req_t>     l2_req;
    sc_out<bool>           l2_req_ready;

    sc_out<bool>           l2_resp_valid;
    sc_out<l2_if_resp_t>   l2_resp;
    sc_in<bool>            l2_resp_ready;

    //  tag_memory port 
    sc_out<bool>                    tm_read_enable;
    sc_out<sc_uint<TM_INDEX_BITS>>  tm_index;         // shared read/write index
    sc_in<sc_uint<TM_TAG_BITS>>     tm_tag_way0;
    sc_in<sc_uint<TM_TAG_BITS>>     tm_tag_way1;
    sc_in<sc_uint<TM_TAG_BITS>>     tm_tag_way2;
    sc_in<sc_uint<TM_TAG_BITS>>     tm_tag_way3;
    sc_in<sc_uint<TM_NUM_WAYS>>     tm_tag_valid;

    sc_out<bool>                    tm_write_enable;
    sc_out<sc_uint<2>>              tm_write_way;
    sc_out<sc_uint<TM_TAG_BITS>>    tm_tag_in;
    sc_out<bool>                    tm_valid_in;

    //  tag_compare port 
    // (tag_way*/tag_valid are wired straight from tag_memory to
    //  tag_compare in the top module -- this module only needs to supply
    //  the request's own tag and read back the verdict)
    sc_out<sc_uint<TC_TAG_BITS>>    tc_req_tag;
    sc_in<bool>                     tc_hit;
    sc_in<bool>                     tc_miss;
    sc_in<sc_uint<2>>               tc_hit_way;

    //  srrip_controller port 
    sc_out<bool>                    sr_req_valid;
    sc_out<sc_uint<INDEX_BITS>>     sr_index;
    sc_out<bool>                    sr_hit;
    sc_out<sc_uint<2>>              sr_hit_way;
    sc_in<sc_uint<2>>               sr_victim_way;
    sc_in<bool>                     sr_victim_valid;

    //  data_array port 
    sc_out<bool>                     da_rd_en;
    sc_out<sc_uint<11>>              da_rd_set;
    sc_out<sc_uint<2>>               da_rd_way;
    sc_in<sc_biguint<LINE_BITS>>     da_rd_data;
    sc_in<bool>                      da_rd_valid;
    sc_in<bool>                      da_rd_dirty;

    sc_out<bool>                     da_wr_en;
    sc_out<sc_uint<11>>              da_wr_set;
    sc_out<sc_uint<2>>               da_wr_way;
    sc_out<sc_biguint<LINE_BITS>>    da_wr_data;
    sc_out<bool>                     da_wr_valid;
    sc_out<bool>                     da_wr_dirty;

    //  mshr_table: allocate / secondary-merge port 
    sc_out<bool>                        mshr_alloc_req;
    sc_out<sc_uint<TM_INDEX_BITS>>      mshr_alloc_index;
    sc_out<sc_uint<TM_TAG_BITS>>        mshr_alloc_tag;
    sc_out<sc_uint<2>>                  mshr_alloc_way;
    sc_out<bool>                        mshr_alloc_victim_dirty;
    sc_out<sc_uint<TM_TAG_BITS>>        mshr_alloc_victim_tag;
    sc_out<sc_biguint<LINE_BITS>>       mshr_alloc_victim_data;
    sc_out<sc_uint<GTAG_W>>             mshr_alloc_gtag;
    sc_out<req_op_t>                    mshr_alloc_op;
    sc_out<bool>                        mshr_alloc_sub_sel;
    sc_out<sc_biguint<L1_LINE_BITS>>    mshr_alloc_wdata;
    sc_out<sc_uint<L1_LINE_BYTES>>      mshr_alloc_wmask;
    sc_in<bool>                         mshr_alloc_ready;
    sc_in<bool>                         mshr_alloc_secondary_hit;
    sc_in<bool>                         mshr_alloc_full_and_write_conflict;

    //  mshr_table: fill-commit port (mshr -> here) 
    sc_in<bool>                         mshr_commit_valid;
    sc_in<sc_uint<TM_INDEX_BITS>>       mshr_commit_index;
    sc_in<sc_uint<2>>                   mshr_commit_way;
    sc_in<sc_uint<TM_TAG_BITS>>         mshr_commit_tag;
    sc_in<sc_biguint<LINE_BITS>>        mshr_commit_data;
    sc_in<bool>                         mshr_commit_dirty;

    //  mshr_table: response port (mshr -> here -> L1, arbitrated) 
    sc_in<bool>            mshr_resp_valid;
    sc_in<l2_if_resp_t>    mshr_resp;
    sc_out<bool>            mshr_resp_ready;

    //  State 
    gc_state_t    state;
    gc_request_t  cur;

    //  Process 
    void do_control();

    SC_CTOR(global_control) {
        state = GC_IDLE;
        cur.valid = false;

        SC_METHOD(do_control);
        sensitive << clk.pos();
        dont_initialize();
    }
};

#endif

