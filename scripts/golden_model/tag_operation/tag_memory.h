
#ifndef TAG_MEMORY_H
#define TAG_MEMORY_H

#include <systemc.h>

// ---- Cache geometry (keep in sync with srrip_controller.h) ----
static const unsigned TM_NUM_SETS   = 2048;  // 512KB / (64B * 4-way)
static const unsigned TM_NUM_WAYS   = 4;
static const unsigned TM_INDEX_BITS = 11;    // log2(2048)
static const unsigned TM_OFFSET_BITS = 6;    // log2(64B line)
// INTEGRATION FIX: was 32 (a placeholder "change if needed" assumption).
// The L1<->L2 and L2<->LLC interfaces (L1_interface.cpp / LLC_interface.cpp)
// both carry a 64-bit address (ADDR_W / LLC_ADDR_W), so the tag array must
// be sized for a 64-bit address or the top-level tag extracted from a real
// request would not match what's stored here. TM_TAG_BITS recomputes to 47.
static const unsigned TM_ADDR_BITS  = 64;
static const unsigned TM_TAG_BITS   = TM_ADDR_BITS - TM_INDEX_BITS - TM_OFFSET_BITS; // 15

SC_MODULE(tag_memory) {

    //  Ports 
    sc_in<bool>                    clk;
    sc_in<bool>                    rst_n;        // active-low sync reset

    //  Read port 
    sc_in<bool>                    tag_read_enable;
    sc_in<sc_uint<TM_INDEX_BITS> > index;         // shared index for read & write

    sc_out<sc_uint<TM_TAG_BITS> >  tag_way0;
    sc_out<sc_uint<TM_TAG_BITS> >  tag_way1;
    sc_out<sc_uint<TM_TAG_BITS> >  tag_way2;
    sc_out<sc_uint<TM_TAG_BITS> >  tag_way3;
    sc_out<sc_uint<TM_NUM_WAYS> >  tag_valid;     // 1 bit per way: {way3,way2,way1,way0}

    //  Write port (fill after a miss) 
    sc_in<bool>                    write_enable;
    sc_in<sc_uint<2> >             write_way;     // which way to store into (0..3)
    sc_in<sc_uint<TM_TAG_BITS> >   tag_in;
    sc_in<bool>                    valid_in;      // valid bit to set for that way

    //  Storage 
    // tag_table[set][way]   -- the actual tag array
    // valid_table[set][way] -- one valid bit per (set, way)
    sc_uint<TM_TAG_BITS> tag_table[TM_NUM_SETS][TM_NUM_WAYS];
    bool                 valid_table[TM_NUM_SETS][TM_NUM_WAYS];

    //  Process 
    void do_tag_mem();

    SC_CTOR(tag_memory) {
        SC_METHOD(do_tag_mem);
        sensitive << clk.pos();
        dont_initialize();

        for (unsigned s = 0; s < TM_NUM_SETS; s++)
            for (unsigned w = 0; w < TM_NUM_WAYS; w++) {
                tag_table[s][w]   = 0;
                valid_table[s][w] = false;   // all lines invalid at reset
            }
    }
};

#endif

