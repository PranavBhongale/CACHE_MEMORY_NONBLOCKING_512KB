
#ifndef LLC_INTERFACE_H
#define LLC_INTERFACE_H
#include <systemc.h>

// Parameters 
static const int LLC_ADDR_W     = 64;
static const int LLC_LINE_BYTES = 64;
static const int LLC_LINE_BITS  = LLC_LINE_BYTES * 8;   // 512
static const int L2_MSHR_ENTRIES = 8;
static const int LLC_TAG_W    = 3;                      // log2(L2_MSHR_ENTRIES)

enum l2_llc_req_op_t  { LLC_REQ_READ, LLC_REQ_WRITE_BACK };
enum l2_llc_resp_op_t { LLC_RESP_FILL, LLC_RESP_WB_ACK };

//  Request packet L2 -> LLC
struct l2_llc_req_t {
    bool                       valid;
    l2_llc_req_op_t             op;
    sc_uint<LLC_ADDR_W>             addr;   // 64B-aligned, matches both line sizes
    sc_uint<LLC_TAG_W>               tag;   // reuses L2's own MSHR index directly
    sc_biguint<LLC_LINE_BITS>  wdata;   // full 64B writeback data
    sc_uint<LLC_LINE_BYTES>    wmask;   // byte mask, in case eviction is partially dirty

    bool operator==(const l2_llc_req_t& o) const {
        return valid==o.valid && op==o.op && addr==o.addr && tag==o.tag
            && wdata==o.wdata && wmask==o.wmask;
    }
};

inline ostream& operator<<(ostream& os, const l2_llc_req_t& r) {
    os << "l2_llc_req(addr=" << r.addr.to_string(SC_HEX) << " tag=" << r.tag << ")";
    return os;
}
inline void sc_trace(sc_trace_file* tf, const l2_llc_req_t& r, const std::string& name) {
    sc_trace(tf, r.valid, name + ".valid");
    sc_trace(tf, r.addr,  name + ".addr");
    sc_trace(tf, r.tag,   name + ".tag");
}

//  Response packet LLC -> L2
struct l2_llc_resp_t {
    bool                       valid;
    l2_llc_resp_op_t             op;
    sc_uint<LLC_TAG_W>               tag;   // echoes the L2 MSHR index
    sc_biguint<LLC_LINE_BITS>   data;   // full 64B line on fill
    bool                        error;

    bool operator==(const l2_llc_resp_t& o) const {
        return valid==o.valid && op==o.op && tag==o.tag
            && data==o.data && error==o.error;
    }
};


inline ostream& operator<<(ostream& os, const l2_llc_resp_t& r) {
    os << "l2_llc_resp(tag=" << r.tag << ")";
    return os;
}

inline void sc_trace(sc_trace_file* tf, const l2_llc_resp_t& r, const std::string& name) {
    sc_trace(tf, r.valid, name + ".valid");
    sc_trace(tf, r.tag,   name + ".tag");
}

//  L2-side interface module 
// Point-to-point (no arbitration needed for a single L2). This
// is where L2's MSHR fill/eviction logic hands off to LLC and
// receives fills back, matched purely by tag.
SC_MODULE(l2_llc_if) {
    sc_in<bool> clk;
    sc_in<bool> rst_n;

    //  L2-facing side (driven by L2's MSHR controller) 
    sc_in<l2_llc_req_t>   l2_req;
    sc_out<bool>          l2_req_ready;
    sc_out<l2_llc_resp_t> l2_resp;
    sc_in<bool>           l2_resp_ready;

    //  LLC-facing side 
    sc_out<bool>              llc_req_valid;
    sc_out<sc_uint<LLC_ADDR_W>>   llc_req_addr;
    sc_out<l2_llc_req_op_t>   llc_req_op;
    sc_out<sc_uint<LLC_TAG_W>>    llc_req_tag;
    sc_out<sc_biguint<LLC_LINE_BITS>> llc_req_wdata;
    sc_out<sc_uint<LLC_LINE_BYTES>>   llc_req_wmask;
    sc_in<bool>                llc_req_ready;

    sc_in<bool>                llc_resp_valid;
    sc_in<sc_uint<LLC_TAG_W>>      llc_resp_tag;
    sc_in<l2_llc_resp_op_t>    llc_resp_op;
    sc_in<sc_biguint<LLC_LINE_BITS>> llc_resp_data;
    sc_in<bool>                llc_resp_error;
    sc_out<bool>               llc_resp_ready;

    void forward_req() {
        if (!rst_n.read()) {
            llc_req_valid.write(false);
            l2_req_ready.write(false);
            return;
        }
        l2_llc_req_t r = l2_req.read();
        llc_req_valid.write(r.valid);
        llc_req_addr.write(r.addr);
        llc_req_op.write(r.op);
        llc_req_tag.write(r.tag);       // MSHR index passed straight through
        llc_req_wdata.write(r.wdata);
        llc_req_wmask.write(r.wmask);
        l2_req_ready.write(llc_req_ready.read());
    }

    void forward_resp() {
        if (!rst_n.read()) {
            l2_resp.write(l2_llc_resp_t{false, LLC_RESP_FILL, 0, 0, false});
            llc_resp_ready.write(false);
            return;
        }
        l2_llc_resp_t r;
        r.valid = llc_resp_valid.read();
        r.op    = llc_resp_op.read();
        r.tag   = llc_resp_tag.read();  // L2 matches this directly against its MSHR
        r.data  = llc_resp_data.read();
        r.error = llc_resp_error.read();
        l2_resp.write(r);
        llc_resp_ready.write(l2_resp_ready.read());
    }

    SC_CTOR(l2_llc_if) {
        SC_METHOD(forward_req);
        sensitive << l2_req << llc_req_ready << rst_n << clk.pos();

        SC_METHOD(forward_resp);
        sensitive << llc_resp_valid << llc_resp_tag << llc_resp_op
                   << llc_resp_data << llc_resp_error << l2_resp_ready
                   << rst_n << clk.pos();
    }
};

#endif // LLC_INTERFACE_H

