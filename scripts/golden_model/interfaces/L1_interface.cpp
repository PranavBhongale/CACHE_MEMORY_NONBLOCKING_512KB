#pragma once
#include <systemc.h>



//  Parameters 
static const int ADDR_W        = 64;
static const int L1_LINE_BYTES = 32;
static const int L2_LINE_BYTES = 64;
static const int L1_LINE_BITS  = L1_LINE_BYTES * 8;   // 256
static const int L2_LINE_BITS  = L2_LINE_BYTES * 8;   // 512
static const int MSHR_ENTRIES  = 8;
static const int TAG_W         = 3;                   // log2(MSHR_ENTRIES)
static const int GTAG_W        = TAG_W + 1;            // +1 bit for src id after arb

enum req_op_t  { REQ_READ, REQ_WRITE_BACK };
enum resp_op_t { RESP_FILL, RESP_WB_ACK };

//Request packet (L1 -> arbiter), local tag
struct l2_req_t {
    bool                     valid;
    req_op_t                 op;
    sc_uint<ADDR_W>          addr;        // L2-line (64B) aligned address
    sc_uint<TAG_W>           tag;         // per-requester MSHR tag
    bool                     sub_sel;     // which 32B half this access targets
    sc_biguint<L1_LINE_BITS> wdata;       // writeback data (32B)
    sc_uint<L1_LINE_BYTES>   wmask;       // byte-enable mask for writeback

    bool operator==(const l2_req_t& o) const {
        return valid==o.valid && op==o.op && addr==o.addr && tag==o.tag
            && sub_sel==o.sub_sel && wdata==o.wdata && wmask==o.wmask;
    }
};
inline ostream& operator<<(ostream& os, const l2_req_t& r) {
    os << "req(addr=" << r.addr.to_string(SC_HEX) << " tag=" << r.tag << ")";
    return os;
}
inline void sc_trace(sc_trace_file* tf, const l2_req_t& r, const std::string& name) {
    sc_trace(tf, r.valid, name + ".valid");
    sc_trace(tf, r.addr,  name + ".addr");
    sc_trace(tf, r.tag,   name + ".tag");
}

//  Response packet (arbiter -> L1), local tag 
struct l2_resp_t {
    bool                     valid;
    resp_op_t                op;
    sc_uint<TAG_W>           tag;         // echoes the requester's tag
    bool                     sub_sel;     // which 32B half `data` corresponds to
    sc_biguint<L2_LINE_BITS> data;        // full 64B line (refill installs both halves)
    bool                     error;

    bool operator==(const l2_resp_t& o) const {
        return valid==o.valid && op==o.op && tag==o.tag
            && sub_sel==o.sub_sel && data==o.data && error==o.error;
    }
};
inline ostream& operator<<(ostream& os, const l2_resp_t& r) {
    os << "resp(tag=" << r.tag << ")";
    return os;
}
inline void sc_trace(sc_trace_file* tf, const l2_resp_t& r, const std::string& name) {
    sc_trace(tf, r.valid, name + ".valid");
    sc_trace(tf, r.tag,   name + ".tag");
}

//  L2-facing request packet, global tag 
// NOTE: deliberately no `valid` field. This struct is the payload half
// of a valid/data/ready channel; `valid` is carried by the companion
// sc_out<bool>/sc_in<bool> line so it lines up 1:1 with
// sync_fifo::in_valid/in_data and out_valid/out_data. Don't add a
// valid bit back in here or you get two sources of truth for it.
struct l2_if_req_t {
    req_op_t                 op;
    sc_uint<ADDR_W>          addr;
    sc_uint<GTAG_W>          gtag;        // {local_tag, src_bit}; src_bit 0=I$, 1=D$
    bool                     sub_sel;
    sc_biguint<L1_LINE_BITS> wdata;
    sc_uint<L1_LINE_BYTES>   wmask;

    l2_if_req_t() : op(REQ_READ), addr(0), gtag(0), sub_sel(false), wdata(0), wmask(0) {}

    bool operator==(const l2_if_req_t& o) const {
        return op==o.op && addr==o.addr && gtag==o.gtag
            && sub_sel==o.sub_sel && wdata==o.wdata && wmask==o.wmask;
    }
};
inline ostream& operator<<(ostream& os, const l2_if_req_t& r) {
    os << "l2_if_req(addr=" << r.addr.to_string(SC_HEX) << " gtag=" << r.gtag << ")";
    return os;
}
inline void sc_trace(sc_trace_file* tf, const l2_if_req_t& r, const std::string& name) {
    sc_trace(tf, r.addr, name + ".addr");
    sc_trace(tf, r.gtag, name + ".gtag");
}

//  L2-facing response packet, global tag
struct l2_if_resp_t {
    resp_op_t                op;
    sc_uint<GTAG_W>          gtag;
    bool                     sub_sel;
    sc_biguint<L2_LINE_BITS> data;
    bool                     error;

    l2_if_resp_t() : op(RESP_FILL), gtag(0), sub_sel(false), data(0), error(false) {}

    bool operator==(const l2_if_resp_t& o) const {
        return op==o.op && gtag==o.gtag
            && sub_sel==o.sub_sel && data==o.data && error==o.error;
    }
};
inline ostream& operator<<(ostream& os, const l2_if_resp_t& r) {
    os << "l2_if_resp(gtag=" << r.gtag << ")";
    return os;
}
inline void sc_trace(sc_trace_file* tf, const l2_if_resp_t& r, const std::string& name) {
    sc_trace(tf, r.gtag, name + ".gtag");
}

//  Arbiter / tag-remap interface module 
// Sits between L1I, L1D and the (now buffered) L2 port.
// Fixed-priority arbitration on the request path (I$ always wins
// over D$ — a stalled fetch stalls the whole pipeline behind it,
// while a stalled load can often be tolerated a cycle longer).
// Response path is routed purely by the embedded source bit in
// the global tag — no arbitration needed there since L2 only
// drives one response per cycle.
SC_MODULE(l1_l2_arbiter) {
    sc_in<bool> clk;
    sc_in<bool> rst_n;

    //  L1I client port 
    sc_in<l2_req_t>   i_req;
    sc_out<bool>      i_req_ready;
    sc_out<l2_resp_t> i_resp;
    sc_in<bool>       i_resp_ready;

    //  L1D client port
    sc_in<l2_req_t>   d_req;
    sc_out<bool>      d_req_ready;
    sc_out<l2_resp_t> d_resp;
    sc_in<bool>       d_resp_ready;

    //  L2-facing port (bundled payload + global tag) 
    // Shape matches sync_fifo<T,DEPTH>'s in_valid/in_data/in_ready
    // (request side) and out_valid/out_data/out_ready (response side)
    // exactly, so it plugs straight into the buffer stage in l1_l2_top.
    sc_out<bool>          l2_req_valid;
    sc_out<l2_if_req_t>   l2_req;
    sc_in<bool>           l2_req_ready;

    sc_in<bool>           l2_resp_valid;
    sc_in<l2_if_resp_t>   l2_resp;
    sc_out<bool>          l2_resp_ready;

    //  Request arbitration: fixed priority to I$, else D$ 
    void arbitrate_req() {
        if (!rst_n.read()) {
            l2_req_valid.write(false);
            l2_req.write(l2_if_req_t());
            i_req_ready.write(false);
            d_req_ready.write(false);
            return;
        }

        l2_req_t i_r = i_req.read();
        l2_req_t d_r = d_req.read();
        bool grant_i = i_r.valid;                // I$ has fixed priority
        bool grant_d = d_r.valid && !grant_i;

        l2_if_req_t out;

        if (grant_i) {
            out.op      = i_r.op;
            out.addr    = i_r.addr;
            out.gtag    = (i_r.tag, sc_uint<1>(0));   // src bit 0 = I$
            out.sub_sel = i_r.sub_sel;
            out.wdata   = i_r.wdata;
            out.wmask   = i_r.wmask;

            l2_req_valid.write(true);
            l2_req.write(out);
            i_req_ready.write(l2_req_ready.read());
            d_req_ready.write(false);
        } else if (grant_d) {
            out.op      = d_r.op;
            out.addr    = d_r.addr;
            out.gtag    = (d_r.tag, sc_uint<1>(1));   // src bit 1 = D$
            out.sub_sel = d_r.sub_sel;
            out.wdata   = d_r.wdata;
            out.wmask   = d_r.wmask;

            l2_req_valid.write(true);
            l2_req.write(out);
            d_req_ready.write(l2_req_ready.read());
            i_req_ready.write(false);
        } else {
            l2_req_valid.write(false);
            l2_req.write(l2_if_req_t());
            i_req_ready.write(false);
            d_req_ready.write(false);
        }
    }

    //  Response routing: pure demux on the source bit 
    void route_resp() {
        if (!rst_n.read()) {
            i_resp.write(l2_resp_t{false, RESP_FILL, 0, false, 0, false});
            d_resp.write(l2_resp_t{false, RESP_FILL, 0, false, 0, false});
            l2_resp_ready.write(false);
            return;
        }

        bool         resp_valid = l2_resp_valid.read();
        l2_if_resp_t in         = l2_resp.read();

        bool           src_is_d  = in.gtag[0];                       // bit 0 = source id
        sc_uint<TAG_W> local_tag = in.gtag.range(GTAG_W - 1, 1);

        l2_resp_t r;
        r.valid   = resp_valid;
        r.op      = in.op;
        r.tag     = local_tag;
        r.sub_sel = in.sub_sel;
        r.data    = in.data;
        r.error   = in.error;

        if (resp_valid && src_is_d) {
            d_resp.write(r);
            i_resp.write(l2_resp_t{false, RESP_FILL, 0, false, 0, false});
            l2_resp_ready.write(d_resp_ready.read());
        } else if (resp_valid) {
            i_resp.write(r);
            d_resp.write(l2_resp_t{false, RESP_FILL, 0, false, 0, false});
            l2_resp_ready.write(i_resp_ready.read());
        } else {
            i_resp.write(l2_resp_t{false, RESP_FILL, 0, false, 0, false});
            d_resp.write(l2_resp_t{false, RESP_FILL, 0, false, 0, false});
            l2_resp_ready.write(false);
        }
    }

    SC_CTOR(l1_l2_arbiter) {
        SC_METHOD(arbitrate_req);
        sensitive << i_req << d_req << l2_req_ready << rst_n << clk.pos();

        SC_METHOD(route_resp);
        sensitive << l2_resp_valid << l2_resp << i_resp_ready
                   << d_resp_ready << rst_n << clk.pos();
    }
};

