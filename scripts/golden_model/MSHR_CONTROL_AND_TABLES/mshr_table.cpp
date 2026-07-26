// mshr_table.cpp
#include "mshr_table_interface.h"


void mshr_table::do_mshr() {

    if (!rst_n.read()) {
        for (unsigned i = 0; i < MSHR_ENTRIES; i++)
            reset_entry(entries[i]);

        llc_req_valid.write(false);
        llc_req.write(l2_llc_req_t());
        llc_resp_ready.write(false);

        commit_valid.write(false);
        resp_valid.write(false);
        resp.write(l2_if_resp_t());

        alloc_ready.write(false);
        alloc_secondary_hit.write(false);
        alloc_full_and_write_conflict.write(false);
        return;
    }

    // default outputs each cycle unless overridden below
    bool             out_req_valid = false;
    l2_llc_req_t     out_req       = l2_llc_req_t();
    bool             out_commit_valid = false;
    sc_uint<TM_INDEX_BITS> out_commit_index = 0;
    sc_uint<2>              out_commit_way   = 0;
    sc_uint<TM_TAG_BITS>    out_commit_tag   = 0;
    sc_biguint<LLC_LINE_BITS> out_commit_data = 0;
    bool             out_commit_dirty = false;
    bool             out_resp_valid = false;
    l2_if_resp_t     out_resp;   // default-constructed; .valid is carried by out_resp_valid, not a field


    // 1) Drain ONE pending response (lowest-index entry in MSHR_RESP).
    //    valid is asserted independent of resp_ready (that's what makes
    //    it a real valid/ready handshake); only the *advance* -- moving
    //    resp_next forward, or freeing the entry -- is gated on
    //    resp_ready actually being high this same cycle. Gating valid
    //    itself on ready would deadlock (ready side waits to see valid,
    //    valid side waits to see ready -- neither ever moves first).
    {
        for (unsigned i = 0; i < MSHR_ENTRIES; i++) {
            mshr_entry_t &e = entries[i];
            if (e.valid && e.state == MSHR_RESP) {

                bool sending = false;
                int  next_val = e.resp_next;

                if (e.resp_next == -1) {
                    // primary requester's response
                    out_resp.op      = (e.op == REQ_WRITE_BACK) ? RESP_WB_ACK : RESP_FILL;
                    out_resp.gtag    = e.gtag;
                    out_resp.sub_sel = e.sub_sel;
                    out_resp.data    = e.fill_data;
                    out_resp.error   = false;
                    next_val = 0;
                    sending = true;
                } else if ((unsigned)e.resp_next < e.num_sec) {
                    // a merged secondary reader
                    unsigned s = (unsigned)e.resp_next;
                    out_resp.op      = RESP_FILL;               // secondaries are reads only
                    out_resp.gtag    = e.sec_gtag[s];
                    out_resp.sub_sel = e.sec_sub_sel[s];
                    out_resp.data    = e.fill_data;
                    out_resp.error   = false;
                    next_val = (int)(s + 1);
                    sending = true;
                }

                if (sending) {
                    out_resp_valid = true;
                    if (resp_ready.read()) {
                        e.resp_next = next_val;
                        if ((unsigned)e.resp_next >= e.num_sec) {
                            // all responses (primary + secondaries) drained -> free the entry
                            reset_entry(e);
                        }
                    }
                    break; // one response per cycle
                }
            }
        }
    }

    // 2) Issue ONE LLC request (lowest-index entry needing the port)
    for (unsigned i = 0; i < MSHR_ENTRIES; i++) {
        mshr_entry_t &e = entries[i];
        if (!e.valid) continue;

        if (e.state == MSHR_WB_SEND) {
            l2_llc_req_t r;
            r.valid = true;
            r.op    = LLC_REQ_WRITE_BACK;
            // reconstruct the victim's OLD full line address: same index, OLD tag
            r.addr  = (sc_uint<LLC_ADDR_W>(e.wb_tag) << (TM_INDEX_BITS + 6))
                    | (sc_uint<LLC_ADDR_W>(e.index)  << 6);
            r.tag   = sc_uint<LLC_TAG_W>(i);          // MSHR index == LLC tag
            r.wdata = e.wb_data;
            r.wmask = ~sc_uint<LLC_LINE_BYTES>(0);    // full-line writeback
            out_req_valid = true;
            out_req       = r;
            if (llc_req_ready.read())
                e.state = MSHR_WB_WAIT;
            break; // one request per cycle
        }
        if (e.state == MSHR_FILL_SEND) {
            l2_llc_req_t r;
            r.valid = true;
            r.op    = LLC_REQ_READ;
            r.addr  = (sc_uint<LLC_ADDR_W>(e.line_tag) << (TM_INDEX_BITS + 6))
                    | (sc_uint<LLC_ADDR_W>(e.index)    << 6);
            r.tag   = sc_uint<LLC_TAG_W>(i);
            r.wdata = 0;
            r.wmask = 0;
            out_req_valid = true;
            out_req       = r;
            if (llc_req_ready.read())
                e.state = MSHR_FILL_WAIT;
            break;
        }
    }

    // 3) Consume an LLC response arriving this cycle (matched by tag)
    if (llc_resp_valid.read()) {
        l2_llc_resp_t r = llc_resp.read();
        unsigned idx = r.tag.to_uint();
        if (idx < MSHR_ENTRIES) {
            mshr_entry_t &e = entries[idx];
            if (e.valid && e.state == MSHR_WB_WAIT && r.op == LLC_RESP_WB_ACK) {
                e.state = MSHR_FILL_SEND;      // eviction done -> now fetch the new line
            } else if (e.valid && e.state == MSHR_FILL_WAIT && r.op == LLC_RESP_FILL) {
                e.fill_data = r.data;
                e.state     = MSHR_COMMIT;
            }
        }
    }

    // 4) Commit ONE just-filled entry (apply any pending write-merge here,
    //    then hand the tuple to global_control to install into the arrays)
    for (unsigned i = 0; i < MSHR_ENTRIES; i++) {
        mshr_entry_t &e = entries[i];
        if (e.valid && e.state == MSHR_COMMIT) {

            bool dirty = false;
            if (e.op == REQ_WRITE_BACK) {
                // merge the primary writeback's bytes into the fetched line
                unsigned base = e.sub_sel ? L1_LINE_BITS : 0;
                for (unsigned b = 0; b < L1_LINE_BYTES; b++) {
                    if (e.wmask[b]) {
                        e.fill_data.range(base + b*8 + 7, base + b*8) = e.wdata.range(b*8 + 7, b*8);
                    }
                }
                dirty = true;
            }

            out_commit_valid = true;
            out_commit_index = e.index;
            out_commit_way   = e.way;
            out_commit_tag   = e.line_tag;
            out_commit_data  = e.fill_data;
            out_commit_dirty = dirty;

            e.state    = MSHR_RESP;
            e.resp_next = -1;
            break; // one commit per cycle
        }
    }

    // 5) Accept a new allocation / secondary-merge request
    bool secondary_hit = false;
    bool write_conflict = false;
    bool have_free      = false;
    int  free_idx        = -1;

    for (unsigned i = 0; i < MSHR_ENTRIES; i++) {
        if (!entries[i].valid) { have_free = true; if (free_idx < 0) free_idx = (int)i; }
    }

    if (alloc_req.read()) {
        sc_uint<TM_INDEX_BITS> a_index = alloc_index.read();
        sc_uint<TM_TAG_BITS>   a_tag   = alloc_tag.read();
        req_op_t                a_op    = alloc_op.read();

        int match_idx = -1;
        for (unsigned i = 0; i < MSHR_ENTRIES; i++) {
            mshr_entry_t &e = entries[i];
            if (e.valid && e.index == a_index && e.line_tag == a_tag) { match_idx = (int)i; break; }
        }

        if (match_idx >= 0) {
            mshr_entry_t &e = entries[(unsigned)match_idx];
            if (a_op == REQ_READ) {
                if (e.num_sec < MSHR_MAX_SEC && e.state != MSHR_RESP) {
                    e.sec_gtag[e.num_sec]    = alloc_gtag.read();
                    e.sec_sub_sel[e.num_sec] = alloc_sub_sel.read();
                    e.num_sec++;
                    secondary_hit = true;
                }
                // else: no free secondary slot -- global_control must retry
                // this cycle (alloc_ready/secondary_hit both read as false)
            } else {
                // a WRITE_BACK colliding with an in-flight entry is not merged
                // (would race the primary's own merge into fill_data) --
                // global_control must stall and retry once the entry frees.
                write_conflict = true;
            }
        } else if (have_free) {
            mshr_entry_t &e = entries[(unsigned)free_idx];
            reset_entry(e);
            e.valid    = true;
            e.index    = a_index;
            e.line_tag = a_tag;
            e.way      = alloc_way.read();
            e.need_wb  = alloc_victim_dirty.read();
            e.wb_tag   = alloc_victim_tag.read();
            e.wb_data  = alloc_victim_data.read();
            e.gtag     = alloc_gtag.read();
            e.op       = a_op;
            e.sub_sel  = alloc_sub_sel.read();
            e.wdata    = alloc_wdata.read();
            e.wmask    = alloc_wmask.read();
            e.state    = e.need_wb ? MSHR_WB_SEND : MSHR_FILL_SEND;
        }
        // else: no free entry and no match -- global_control must retry
        // (alloc_ready reads false this cycle)
    }

    // recompute "have_free" post-allocation for next cycle's ready signal
    have_free = false;
    for (unsigned i = 0; i < MSHR_ENTRIES; i++)
        if (!entries[i].valid) { have_free = true; break; }

    // Drive all outputs
    llc_req_valid.write(out_req_valid);
    llc_req.write(out_req);
    llc_resp_ready.write(true);   // always able to accept/match a fill or WB-ack

    commit_valid.write(out_commit_valid);
    commit_index.write(out_commit_index);
    commit_way.write(out_commit_way);
    commit_tag.write(out_commit_tag);
    commit_data.write(out_commit_data);
    commit_dirty.write(out_commit_dirty);

    resp_valid.write(out_resp_valid);
    resp.write(out_resp);

    alloc_ready.write(have_free);
    alloc_secondary_hit.write(secondary_hit);
    alloc_full_and_write_conflict.write(write_conflict);
}
