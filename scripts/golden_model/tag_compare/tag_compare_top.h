// tag_compare.h
// COMBINATIONAL tag comparison for a 4-way set-associative L2 cache
// (512KB, 4-way, 64B line). NOT pipelined -- only 4 ways to compare,
// so it's just 4 parallel equality checks + a priority encoder, all
// resolved in the same cycle the inputs are presented.
//
// Consumes:
//   - the request's own tag (computed upstream from the address)
//   - the 4 way-tags + 4 valid bits read out of tag_memory for that set
// Produces:
//   - hit / miss
//   - hit_way (which way matched, valid only when hit==1)
//
// This module does NOT store anything (that's tag_memory's job) and does
// NOT register its outputs -- it's pure combinational logic sitting
// between tag_memory's read output and whatever consumes hit/hit_way
// (e.g. SRRIP controller, data array way-select mux).

#ifndef TAG_COMPARE_H
#define TAG_COMPARE_H

#include <systemc.h>

static const unsigned TC_NUM_WAYS = 4;

static const unsigned TC_TAG_BITS = 47;   // keep in sync with TM_TAG_BITS

SC_MODULE(tag_compare) {

    //  Ports 
    sc_in<sc_uint<TC_TAG_BITS> >    req_tag;    // tag extracted from the address

    sc_in<sc_uint<TC_TAG_BITS> >    tag_way0;
    sc_in<sc_uint<TC_TAG_BITS> >    tag_way1;
    sc_in<sc_uint<TC_TAG_BITS> >    tag_way2;
    sc_in<sc_uint<TC_TAG_BITS> >    tag_way3;
    sc_in<sc_uint<TC_NUM_WAYS> >    tag_valid;  // 1 bit per way from tag_memory

    sc_out<bool>                    hit;
    sc_out<bool>                    miss;
    sc_out<sc_uint<2> >             hit_way;    // valid only when hit==1

    //  Process 
    void do_compare();

    SC_CTOR(tag_compare) {
        SC_METHOD(do_compare);
        sensitive << req_tag << tag_way0 << tag_way1 << tag_way2 << tag_way3 << tag_valid;
        // no clk -- purely combinational, re-evaluates whenever any input changes
    }
};

#endif

