// l2_cache_top.cpp
// Top-level L2 cache: wires together
//   - tag_operation/tag_memory.cpp        (tag access stage)
//   - tag_compare/tag_compare_top.cpp     (tag compare stage)
//   - SRRIP/srrip_controller_interface.cpp (replacement policy)
//   - data_array/data_array.cpp           (line storage)
//   - MSHR_CONTROL_AND_TABLES/mshr_table_interface.cpp (miss tracking + LLC txns)
//   - GLOBAL_CONTROL/global_control_interface.cpp (pipeline sequencer)
//
// SCOPE: this module IS the L2 cache. It does not instantiate
// l1_l2_arbiter/l1_l2_top or l2_llc_if -- those are the L1<->L2 and
// L2<->LLC glue modules already provided in interfaces/, meant to sit in
// a higher-level system top, one level further out. This module's ports
// are shaped to plug directly into both without adapters:
//   - cpu_* mirrors l1_l2_top's L2-facing port (L1_L2_TOP_INTERFACE.CPP)
//   - mem_* mirrors l2_llc_if's L2-facing port (LLC_interface.cpp)
#ifndef L2_CACHE_TOP_H
#define L2_CACHE_TOP_H

#include <systemc.h>
#include "../GLOBAL_CONTROL/global_control.cpp"
#include "../MSHR_CONTROL_AND_TABLES/mshr_table.cpp"
#include "../tag_operation/tag_memory_function.cpp"
#include "../tag_compare/tag_compare.cpp"
#include "../SRRIP/srrip_controller.cpp"
#include "../data_array/data_array.cpp"

SC_MODULE(l2_cache_top) {

    sc_in<bool> clk;
    sc_in<bool> rst_n;

    //  CPU (L1) side -- mirrors l1_l2_top's L2-facing port
    sc_in<bool>            cpu_req_valid;
    sc_in<l2_if_req_t>     cpu_req;
    sc_out<bool>           cpu_req_ready;

    sc_out<bool>           cpu_resp_valid;
    sc_out<l2_if_resp_t>   cpu_resp;
    sc_in<bool>            cpu_resp_ready;

    //  Memory (LLC) side -- mirrors l2_llc_if's L2-facing port 
    sc_out<bool>            mem_req_valid;
    sc_out<l2_llc_req_t>    mem_req;
    sc_in<bool>              mem_req_ready;

    sc_in<bool>              mem_resp_valid;
    sc_in<l2_llc_resp_t>     mem_resp;
    sc_out<bool>              mem_resp_ready;

    //  Submodules 
    global_control* gc;
    mshr_table*     mshr;
    tag_memory*     tmem;
    tag_compare*    tcmp;
    srrip_controller* srrip;
    data_array*     darr;

    //  Internal wiring signals 
    // tag_memory <-> global_control (+ fan-out to tag_compare)
    sc_signal<bool>                     w_tm_read_enable;
    sc_signal<sc_uint<TM_INDEX_BITS>>   w_tm_index;
    sc_signal<sc_uint<TM_TAG_BITS>>     w_tm_tag_way0, w_tm_tag_way1, w_tm_tag_way2, w_tm_tag_way3;
    sc_signal<sc_uint<TM_NUM_WAYS>>     w_tm_tag_valid;
    sc_signal<bool>                     w_tm_write_enable;
    sc_signal<sc_uint<2>>               w_tm_write_way;
    sc_signal<sc_uint<TM_TAG_BITS>>     w_tm_tag_in;
    sc_signal<bool>                     w_tm_valid_in;

    // tag_compare <-> global_control
    sc_signal<sc_uint<TC_TAG_BITS>>     w_tc_req_tag;
    sc_signal<bool>                      w_tc_hit;
    sc_signal<bool>                      w_tc_miss;
    sc_signal<sc_uint<2>>                w_tc_hit_way;

    // srrip <-> global_control
    sc_signal<bool>              w_sr_req_valid;
    sc_signal<sc_uint<INDEX_BITS>> w_sr_index;
    sc_signal<bool>              w_sr_hit;
    sc_signal<sc_uint<2>>        w_sr_hit_way;
    sc_signal<sc_uint<2>>        w_sr_victim_way;
    sc_signal<bool>              w_sr_victim_valid;

    // data_array <-> global_control
    sc_signal<bool>                    w_da_rd_en;
    sc_signal<sc_uint<11>>             w_da_rd_set;
    sc_signal<sc_uint<2>>              w_da_rd_way;
    sc_signal<sc_biguint<LINE_BITS>>   w_da_rd_data;
    sc_signal<bool>                    w_da_rd_valid;
    sc_signal<bool>                    w_da_rd_dirty;
    sc_signal<bool>                    w_da_wr_en;
    sc_signal<sc_uint<11>>             w_da_wr_set;
    sc_signal<sc_uint<2>>              w_da_wr_way;
    sc_signal<sc_biguint<LINE_BITS>>   w_da_wr_data;
    sc_signal<bool>                    w_da_wr_valid;
    sc_signal<bool>                    w_da_wr_dirty;

    // mshr_table <-> global_control : allocate port
    sc_signal<bool>                        w_alloc_req;
    sc_signal<sc_uint<TM_INDEX_BITS>>      w_alloc_index;
    sc_signal<sc_uint<TM_TAG_BITS>>        w_alloc_tag;
    sc_signal<sc_uint<2>>                  w_alloc_way;
    sc_signal<bool>                        w_alloc_victim_dirty;
    sc_signal<sc_uint<TM_TAG_BITS>>        w_alloc_victim_tag;
    sc_signal<sc_biguint<LINE_BITS>>       w_alloc_victim_data;
    sc_signal<sc_uint<GTAG_W>>             w_alloc_gtag;
    sc_signal<req_op_t>                    w_alloc_op;
    sc_signal<bool>                        w_alloc_sub_sel;
    sc_signal<sc_biguint<L1_LINE_BITS>>    w_alloc_wdata;
    sc_signal<sc_uint<L1_LINE_BYTES>>      w_alloc_wmask;
    sc_signal<bool>                        w_alloc_ready;
    sc_signal<bool>                        w_alloc_secondary_hit;
    sc_signal<bool>                        w_alloc_conflict;

    // mshr_table <-> global_control : commit port
    sc_signal<bool>                       w_commit_valid;
    sc_signal<sc_uint<TM_INDEX_BITS>>     w_commit_index;
    sc_signal<sc_uint<2>>                 w_commit_way;
    sc_signal<sc_uint<TM_TAG_BITS>>       w_commit_tag;
    sc_signal<sc_biguint<LINE_BITS>>      w_commit_data;
    sc_signal<bool>                       w_commit_dirty;

    // mshr_table <-> global_control : response arbitration port
    sc_signal<bool>            w_mshr_resp_valid;
    sc_signal<l2_if_resp_t>    w_mshr_resp;
    sc_signal<bool>            w_mshr_resp_ready;

    void build() {
        tmem  = new tag_memory("tmem");
        tcmp  = new tag_compare("tcmp");
        srrip = new srrip_controller("srrip");
        darr  = new data_array("darr");
        mshr  = new mshr_table("mshr");
        gc    = new global_control("gc");

        //  clk / rst_n fan-out 
        tmem->clk(clk);   tmem->rst_n(rst_n);
        // tag_compare has no clk/rst_n ports -- combinational only.
        srrip->clk(clk);  srrip->rst_n(rst_n);
        darr->clk(clk);   darr->rst_n(rst_n);
        mshr->clk(clk);   mshr->rst_n(rst_n);
        gc->clk(clk);     gc->rst_n(rst_n);

        //  CPU-side pass-through 
        gc->l2_req_valid(cpu_req_valid);
        gc->l2_req(cpu_req);
        gc->l2_req_ready(cpu_req_ready);
        gc->l2_resp_valid(cpu_resp_valid);
        gc->l2_resp(cpu_resp);
        gc->l2_resp_ready(cpu_resp_ready);

        //  global_control <-> tag_memory 
        gc->tm_read_enable(w_tm_read_enable);
        gc->tm_index(w_tm_index);
        gc->tm_tag_way0(w_tm_tag_way0);
        gc->tm_tag_way1(w_tm_tag_way1);
        gc->tm_tag_way2(w_tm_tag_way2);
        gc->tm_tag_way3(w_tm_tag_way3);
        gc->tm_tag_valid(w_tm_tag_valid);
        gc->tm_write_enable(w_tm_write_enable);
        gc->tm_write_way(w_tm_write_way);
        gc->tm_tag_in(w_tm_tag_in);
        gc->tm_valid_in(w_tm_valid_in);

        tmem->tag_read_enable(w_tm_read_enable);
        tmem->index(w_tm_index);
        tmem->tag_way0(w_tm_tag_way0);
        tmem->tag_way1(w_tm_tag_way1);
        tmem->tag_way2(w_tm_tag_way2);
        tmem->tag_way3(w_tm_tag_way3);
        tmem->tag_valid(w_tm_tag_valid);
        tmem->write_enable(w_tm_write_enable);
        tmem->write_way(w_tm_write_way);
        tmem->tag_in(w_tm_tag_in);
        tmem->valid_in(w_tm_valid_in);

        //  tag_memory's read output fans out into tag_compare directly 
        tcmp->tag_way0(w_tm_tag_way0);
        tcmp->tag_way1(w_tm_tag_way1);
        tcmp->tag_way2(w_tm_tag_way2);
        tcmp->tag_way3(w_tm_tag_way3);
        tcmp->tag_valid(w_tm_tag_valid);

        //  global_control <-> tag_compare 
        gc->tc_req_tag(w_tc_req_tag);
        gc->tc_hit(w_tc_hit);
        gc->tc_miss(w_tc_miss);
        gc->tc_hit_way(w_tc_hit_way);
        tcmp->req_tag(w_tc_req_tag);
        tcmp->hit(w_tc_hit);
        tcmp->miss(w_tc_miss);
        tcmp->hit_way(w_tc_hit_way);

        //  global_control <-> srrip 
        gc->sr_req_valid(w_sr_req_valid);
        gc->sr_index(w_sr_index);
        gc->sr_hit(w_sr_hit);
        gc->sr_hit_way(w_sr_hit_way);
        gc->sr_victim_way(w_sr_victim_way);
        gc->sr_victim_valid(w_sr_victim_valid);

        srrip->req_valid(w_sr_req_valid);
        srrip->index(w_sr_index);
        srrip->hit(w_sr_hit);
        srrip->hit_way(w_sr_hit_way);
        srrip->victim_way(w_sr_victim_way);
        srrip->victim_valid(w_sr_victim_valid);

        //  global_control <-> data_array 
        gc->da_rd_en(w_da_rd_en);
        gc->da_rd_set(w_da_rd_set);
        gc->da_rd_way(w_da_rd_way);
        gc->da_rd_data(w_da_rd_data);
        gc->da_rd_valid(w_da_rd_valid);
        gc->da_rd_dirty(w_da_rd_dirty);
        gc->da_wr_en(w_da_wr_en);
        gc->da_wr_set(w_da_wr_set);
        gc->da_wr_way(w_da_wr_way);
        gc->da_wr_data(w_da_wr_data);
        gc->da_wr_valid(w_da_wr_valid);
        gc->da_wr_dirty(w_da_wr_dirty);

        darr->rd_en(w_da_rd_en);
        darr->rd_set(w_da_rd_set);
        darr->rd_way(w_da_rd_way);
        darr->rd_data(w_da_rd_data);
        darr->rd_valid(w_da_rd_valid);
        darr->rd_dirty(w_da_rd_dirty);
        darr->wr_en(w_da_wr_en);
        darr->wr_set(w_da_wr_set);
        darr->wr_way(w_da_wr_way);
        darr->wr_data(w_da_wr_data);
        darr->wr_valid(w_da_wr_valid);
        darr->wr_dirty(w_da_wr_dirty);

        //  global_control <-> mshr_table : allocate port 
        gc->mshr_alloc_req(w_alloc_req);
        gc->mshr_alloc_index(w_alloc_index);
        gc->mshr_alloc_tag(w_alloc_tag);
        gc->mshr_alloc_way(w_alloc_way);
        gc->mshr_alloc_victim_dirty(w_alloc_victim_dirty);
        gc->mshr_alloc_victim_tag(w_alloc_victim_tag);
        gc->mshr_alloc_victim_data(w_alloc_victim_data);
        gc->mshr_alloc_gtag(w_alloc_gtag);
        gc->mshr_alloc_op(w_alloc_op);
        gc->mshr_alloc_sub_sel(w_alloc_sub_sel);
        gc->mshr_alloc_wdata(w_alloc_wdata);
        gc->mshr_alloc_wmask(w_alloc_wmask);
        gc->mshr_alloc_ready(w_alloc_ready);
        gc->mshr_alloc_secondary_hit(w_alloc_secondary_hit);
        gc->mshr_alloc_full_and_write_conflict(w_alloc_conflict);

        mshr->alloc_req(w_alloc_req);
        mshr->alloc_index(w_alloc_index);
        mshr->alloc_tag(w_alloc_tag);
        mshr->alloc_way(w_alloc_way);
        mshr->alloc_victim_dirty(w_alloc_victim_dirty);
        mshr->alloc_victim_tag(w_alloc_victim_tag);
        mshr->alloc_victim_data(w_alloc_victim_data);
        mshr->alloc_gtag(w_alloc_gtag);
        mshr->alloc_op(w_alloc_op);
        mshr->alloc_sub_sel(w_alloc_sub_sel);
        mshr->alloc_wdata(w_alloc_wdata);
        mshr->alloc_wmask(w_alloc_wmask);
        mshr->alloc_ready(w_alloc_ready);
        mshr->alloc_secondary_hit(w_alloc_secondary_hit);
        mshr->alloc_full_and_write_conflict(w_alloc_conflict);

        //  mshr_table <-> global_control : commit port 
        mshr->commit_valid(w_commit_valid);
        mshr->commit_index(w_commit_index);
        mshr->commit_way(w_commit_way);
        mshr->commit_tag(w_commit_tag);
        mshr->commit_data(w_commit_data);
        mshr->commit_dirty(w_commit_dirty);

        gc->mshr_commit_valid(w_commit_valid);
        gc->mshr_commit_index(w_commit_index);
        gc->mshr_commit_way(w_commit_way);
        gc->mshr_commit_tag(w_commit_tag);
        gc->mshr_commit_data(w_commit_data);
        gc->mshr_commit_dirty(w_commit_dirty);

        //  mshr_table <-> global_control : response arbitration 
        mshr->resp_valid(w_mshr_resp_valid);
        mshr->resp(w_mshr_resp);
        mshr->resp_ready(w_mshr_resp_ready);

        gc->mshr_resp_valid(w_mshr_resp_valid);
        gc->mshr_resp(w_mshr_resp);
        gc->mshr_resp_ready(w_mshr_resp_ready);

        //  mshr_table <-> LLC (top-level pass-through) 
        mshr->llc_req_valid(mem_req_valid);
        mshr->llc_req(mem_req);
        mshr->llc_req_ready(mem_req_ready);
        mshr->llc_resp_valid(mem_resp_valid);
        mshr->llc_resp(mem_resp);
        mshr->llc_resp_ready(mem_resp_ready);
    }

    SC_CTOR(l2_cache_top)
        : gc(nullptr), mshr(nullptr), tmem(nullptr), tcmp(nullptr), srrip(nullptr), darr(nullptr) {
        build();
    }

    ~l2_cache_top() {
        delete gc; delete mshr; delete tmem; delete tcmp; delete srrip; delete darr;
    }
};

#endif
