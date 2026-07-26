// global_control.cpp
#include "global_control_interface.cpp"

void global_control::do_control() {

    if (!rst_n.read()) {
        state = GC_IDLE;
        cur.valid = false;

        l2_req_ready.write(false);
        l2_resp_valid.write(false);
        l2_resp.write(l2_if_resp_t());

        tm_read_enable.write(false);
        tm_index.write(0);
        tm_write_enable.write(false);
        tm_write_way.write(0);
        tm_tag_in.write(0);
        tm_valid_in.write(false);

        tc_req_tag.write(0);

        sr_req_valid.write(false);
        sr_index.write(0);
        sr_hit.write(false);
        sr_hit_way.write(0);

        da_rd_en.write(false);
        da_rd_set.write(0);
        da_rd_way.write(0);
        da_wr_en.write(false);
        da_wr_set.write(0);
        da_wr_way.write(0);
        da_wr_data.write(0);
        da_wr_valid.write(false);
        da_wr_dirty.write(false);

        mshr_alloc_req.write(false);
        mshr_resp_ready.write(false);
        return;
    }

    // per-cycle defaults (overridden below as needed)
    bool                     out_tm_read_en = false;
    sc_uint<TM_INDEX_BITS>   out_tm_index   = tm_index.read();
    bool                     out_tm_write_en = false;
    sc_uint<2>               out_tm_write_way = 0;
    sc_uint<TM_TAG_BITS>     out_tm_tag_in    = 0;
    bool                     out_tm_valid_in  = false;

    bool                     out_sr_req_valid = false;
    bool                     out_sr_hit       = false;
    sc_uint<2>               out_sr_hit_way   = 0;
    bool                     out_da_rd_en = false;
    sc_uint<11>              out_da_rd_set = 0;
    sc_uint<2>               out_da_rd_way = 0;
    bool                     out_da_wr_en = false;
    sc_uint<11>              out_da_wr_set = 0;
    sc_uint<2>               out_da_wr_way = 0;
    sc_biguint<LINE_BITS>    out_da_wr_data = 0;
    bool                     out_da_wr_valid = false;
    bool                     out_da_wr_dirty = false;

    bool                     out_mshr_alloc_req = false;

    // (a) mshr fill-commit -- always serviced immediately; blocks a new
    //     front-end tag_memory READ from starting this same cycle
    //     (tag_memory's index port is shared between read and write).
    bool commit_this_cycle = mshr_commit_valid.read();
    if (commit_this_cycle) {
        out_tm_write_en  = true;
        out_tm_index     = mshr_commit_index.read();
        out_tm_write_way = mshr_commit_way.read();
        out_tm_tag_in    = mshr_commit_tag.read();
        out_tm_valid_in  = true;

        out_da_wr_en    = true;
        out_da_wr_set   = mshr_commit_index.read();
        out_da_wr_way   = mshr_commit_way.read();
        out_da_wr_data  = mshr_commit_data.read();
        out_da_wr_valid = true;
        out_da_wr_dirty = mshr_commit_dirty.read();
    }

    // (b) response arbitration -- mshr_table's responses win the shared
    //     L1-facing port over this module's own hit response.
    bool mshr_wants_resp = mshr_resp_valid.read();
    bool out_l2_resp_valid = false;
    l2_if_resp_t out_l2_resp;

    if (mshr_wants_resp) {
        out_l2_resp_valid = true;
        out_l2_resp       = mshr_resp.read();
        mshr_resp_ready.write(l2_resp_ready.read());
    } else {
        mshr_resp_ready.write(false);
    }

    // Main FSM
    bool out_l2_req_ready = false;

    switch (state) {

    case GC_IDLE: {
        // Only accept a new request if nothing else needs tag_memory's
        // shared index port this cycle.
        if (!commit_this_cycle) {
            out_l2_req_ready = true;
            if (l2_req_valid.read()) {
                l2_if_req_t r = l2_req.read();
                cur.valid = true;
                cur.req   = r;
                cur.index = r.addr.range(TM_INDEX_BITS + 5, 6);
                cur.tag   = r.addr.range(TM_ADDR_BITS - 1, TM_INDEX_BITS + 6);

                out_tm_read_en = true;
                out_tm_index   = cur.index;

                state = GC_TAG_WAIT;
            }
        }
        break;
    }

    case GC_TAG_WAIT: {
        // tag_memory is capturing the read presented last cycle; nothing
        // else to drive here, just let one edge pass.
        state = GC_COMPARE;
        break;
    }

    case GC_COMPARE: {
        // tag_memory's read has settled -> tag_compare's verdict is valid.
        cur.hit     = tc_hit.read();
        cur.hit_way = tc_hit_way.read();

        cur.way_tag[0] = tm_tag_way0.read();
        cur.way_tag[1] = tm_tag_way1.read();
        cur.way_tag[2] = tm_tag_way2.read();
        cur.way_tag[3] = tm_tag_way3.read();
        cur.way_valid_bits = tm_tag_valid.read();

        out_sr_req_valid = true;   // srrip updates its RRPV table on hits too

        if (cur.hit) {
            out_sr_hit     = true;
            out_sr_hit_way = cur.hit_way;

            out_da_rd_en  = true;
            out_da_rd_set = cur.index;
            out_da_rd_way = cur.hit_way;
            state = GC_DATA;
        } else {
            out_sr_hit = false;   // miss: srrip will compute+return a victim way
            state = GC_VICTIM_WAIT;
        }
        break;
    }

    case GC_DATA: {
        // data_array's read of the hit way is now valid.
        sc_biguint<LINE_BITS> line = da_rd_data.read();

        if (cur.req.op == REQ_WRITE_BACK) {
            // merge the L1 writeback bytes into the current line and
            // write it straight back (write-hit, no LLC traffic needed).
            unsigned base = cur.req.sub_sel ? L1_LINE_BITS : 0;
            for (unsigned b = 0; b < L1_LINE_BYTES; b++) {
                if (cur.req.wmask[b]) {
                    line.range(base + b*8 + 7, base + b*8) = cur.req.wdata.range(b*8 + 7, b*8);
                }
            }
            out_da_wr_en    = true;
            out_da_wr_set   = cur.index;
            out_da_wr_way   = cur.hit_way;
            out_da_wr_data  = line;
            out_da_wr_valid = true;
            out_da_wr_dirty = true;
        }

        cur.line_data = line;
        state = GC_RESPOND;
        break;
    }

    case GC_RESPOND: {
        // Only drive the shared response port if mshr didn't already
        // take it this cycle; otherwise just retry next cycle.
        if (!mshr_wants_resp) {
            l2_if_resp_t r;
            r.op      = (cur.req.op == REQ_WRITE_BACK) ? RESP_WB_ACK : RESP_FILL;
            r.gtag    = cur.req.gtag;
            r.sub_sel = cur.req.sub_sel;
            r.data    = cur.line_data;
            r.error   = false;

            out_l2_resp_valid = true;
            out_l2_resp       = r;

            if (l2_resp_ready.read()) {
                cur.valid = false;
                state = GC_IDLE;
            }
            // else: L1 side not ready -- stay in GC_RESPOND, retry
        }
        break;
    }

    case GC_VICTIM_WAIT: {
        // srrip_controller is capturing req_valid/index/hit this edge.
        state = GC_VICTIM;
        break;
    }

    case GC_VICTIM: {
        // srrip_controller's victim_way/victim_valid are now valid.
        cur.victim_way   = sr_victim_way.read();
        cur.victim_valid = sr_victim_valid.read();

        out_da_rd_en  = true;
        out_da_rd_set = cur.index;
        out_da_rd_way = cur.victim_way;
        state = GC_VICTIM_DATA;
        break;
    }

    case GC_VICTIM_DATA: {
        // data_array's read of the victim way is now valid.
        bool victim_was_valid = da_rd_valid.read();
        bool victim_was_dirty = da_rd_dirty.read();

        cur.need_wb     = victim_was_valid && victim_was_dirty;
        cur.victim_tag  = cur.way_tag[cur.victim_way.to_uint()];
        cur.victim_data = da_rd_data.read();

        out_mshr_alloc_req = true;
        state = GC_ALLOC_WAIT;
        break;
    }

    case GC_ALLOC_WAIT: {
        // mshr_table is capturing alloc_req this edge; keep asserting the
        // same fields (driven generically below via `cur`) until we've
        // seen the outcome in GC_ALLOC_CHECK.
        out_mshr_alloc_req = true;
        state = GC_ALLOC_CHECK;
        break;
    }

    case GC_ALLOC_CHECK: {
        bool ready     = mshr_alloc_ready.read();
        bool secondary = mshr_alloc_secondary_hit.read();
        bool conflict  = mshr_alloc_full_and_write_conflict.read();

        if (ready || secondary) {
            // Either a new entry was allocated, or this request was
            // merged as a secondary reader into an in-flight entry.
            // Either way the response will eventually arrive from
            // mshr_table itself (echoing cur.req.gtag) -- the front end
            // is free to move on.
            cur.valid = false;
            state = GC_IDLE;
        } else {
            // MSHR full with no match, or a write-back collided with an
            // in-flight entry for the same line -- retry the same
            // allocation request next cycle (backpressure).
            (void)conflict;
            out_mshr_alloc_req = true;
            state = GC_ALLOC_WAIT;
        }
        break;
    }

    } // switch

    //
    // Drive mshr_table's allocate-port fields whenever we're asking for
    // an allocation this cycle (GC_VICTIM_DATA / GC_ALLOC_WAIT / retry
    // path in GC_ALLOC_CHECK) -- always sourced from `cur`, which holds
    // the one in-flight front-end request.
    // 
    mshr_alloc_req.write(out_mshr_alloc_req);
    mshr_alloc_index.write(cur.index);
    mshr_alloc_tag.write(cur.tag);
    mshr_alloc_way.write(cur.victim_way);
    mshr_alloc_victim_dirty.write(cur.need_wb);
    mshr_alloc_victim_tag.write(cur.victim_tag);
    mshr_alloc_victim_data.write(cur.victim_data);
    mshr_alloc_gtag.write(cur.req.gtag);
    mshr_alloc_op.write(cur.req.op);
    mshr_alloc_sub_sel.write(cur.req.sub_sel);
    mshr_alloc_wdata.write(cur.req.wdata);
    mshr_alloc_wmask.write(cur.req.wmask);


    // Drive everything else
    l2_req_ready.write(out_l2_req_ready);
    l2_resp_valid.write(out_l2_resp_valid);
    l2_resp.write(out_l2_resp);

    tm_read_enable.write(out_tm_read_en);
    tm_index.write(out_tm_index);
    tm_write_enable.write(out_tm_write_en);
    tm_write_way.write(out_tm_write_way);
    tm_tag_in.write(out_tm_tag_in);
    tm_valid_in.write(out_tm_valid_in);

    tc_req_tag.write(cur.tag);

    sr_req_valid.write(out_sr_req_valid);
    sr_index.write(cur.index);
    sr_hit.write(out_sr_hit);
    sr_hit_way.write(out_sr_hit_way);

    da_rd_en.write(out_da_rd_en);
    da_rd_set.write(out_da_rd_set);
    da_rd_way.write(out_da_rd_way);
    da_wr_en.write(out_da_wr_en);
    da_wr_set.write(out_da_wr_set);
    da_wr_way.write(out_da_wr_way);
    da_wr_data.write(out_da_wr_data);
    da_wr_valid.write(out_da_wr_valid);
    da_wr_dirty.write(out_da_wr_dirty);
}

