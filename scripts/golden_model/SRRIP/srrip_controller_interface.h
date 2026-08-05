// srrip_controller.h
// SRRIP (Static Re-Reference Interval Prediction) replacement policy engine
// Target cache : 512KB, 4-way set-associative, 64B line
//   -> sets   = 524288 / (64 * 4) = 2048
//   -> index  = 11 bits
//   -> ways   = 4
//   -> RRPV   = 2 bits per way (max value = 3)
//
// Matches the block drawn in cache_internal_designe.drawio (CONTROL sheet):
//   inputs  : index bit, hit, hit_way   (if miss, hit_way = 0 / don't care)
//   output  : victim cache way
//   table   : 2-bit counter x way1..way4, one row per set

#ifndef SRRIP_CONTROLLER_H
#define SRRIP_CONTROLLER_H

#include <systemc.h>

//  Cache geometry (change here if the cache config changes) 
static const unsigned NUM_SETS   = 2048;   // 512KB / (64B * 4-way)
static const unsigned NUM_WAYS   = 4;
static const unsigned INDEX_BITS = 11;     // log2(2048)
static const unsigned RRPV_BITS  = 2;      // 2-bit counter, max = 3
static const unsigned RRPV_MAX   = 3;      // "distant"  (never used again soon)
static const unsigned RRPV_LONG  = 2;      // SRRIP insertion value (long re-ref interval)
static const unsigned RRPV_NEAR  = 0;      // set on hit (near-immediate re-reference)

SC_MODULE(srrip_controller) {

    //  Ports 
    sc_in<bool>                  clk;
    sc_in<bool>                  rst_n;      // active-low sync reset

    sc_in<bool>                  req_valid;  // a lookup is happening this cycle
    sc_in<sc_uint<INDEX_BITS> >  index;      // set index
    sc_in<bool>                  hit;        // 1 = hit, 0 = miss
    sc_in<sc_uint<2> >           hit_way;    // valid only when hit==1 (0 on miss, per spec)

    sc_out<sc_uint<2> >          victim_way; // valid only when hit==0 (the way to evict/fill)
    sc_out<bool>                 victim_valid;

    //  Storage: the table in the drawio 
    // rrpv_table[set][way]  -> 2-bit counter (0..3)
    sc_uint<RRPV_BITS> rrpv_table[NUM_SETS][NUM_WAYS];

    //  Process 
    void do_srrip();



    SC_CTOR(srrip_controller) {
        SC_METHOD(do_srrip);
        sensitive << clk.pos();
        dont_initialize();

        // initialize table: SRRIP resets all counters to RRPV_MAX (3)
        // (some SRRIP variants init to RRPV_LONG=2; using MAX at reset is fine since
        //  the very first fill of any line is done through the normal miss path anyway,
        //  which forces RRPV_LONG on insertion.)
        for (unsigned s = 0; s < NUM_SETS; s++)
            for (unsigned w = 0; w < NUM_WAYS; w++)
                rrpv_table[s][w] = RRPV_MAX;
    }
};



#endif

