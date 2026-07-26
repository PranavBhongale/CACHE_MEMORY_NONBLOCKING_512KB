// tag_memory.cpp
#include "tag_memory.h"


void tag_memory::do_tag_mem() {

    // ---- synchronous reset ----
    if (rst_n.read() == false) {
        for (unsigned s = 0; s < TM_NUM_SETS; s++)
            for (unsigned w = 0; w < TM_NUM_WAYS; w++) {
                tag_table[s][w]   = 0;
                valid_table[s][w] = false;
            }

        tag_way0.write(0);
        tag_way1.write(0);
        tag_way2.write(0);
        tag_way3.write(0);
        tag_valid.write(0);
        return;
    }

    unsigned idx = index.read().to_uint();

    // WRITE PATH: store a tag into one way of the set (fill on miss)
    if (write_enable.read()) {
        unsigned w = write_way.read().to_uint();
        tag_table[idx][w]   = tag_in.read();
        valid_table[idx][w] = valid_in.read();
    }

    // READ PATH: return ALL 4 ways' tags + valid bits for this set
    // (no comparison here -- tag_compare module does that downstream)
    if (tag_read_enable.read()) {
        tag_way0.write(tag_table[idx][0]);
        tag_way1.write(tag_table[idx][1]);
        tag_way2.write(tag_table[idx][2]);
        tag_way3.write(tag_table[idx][3]);

        sc_uint<TM_NUM_WAYS> vbits = 0;
        for (unsigned w = 0; w < TM_NUM_WAYS; w++)
            if (valid_table[idx][w]) vbits[w] = 1;

        tag_valid.write(vbits);
    }
    // if tag_read_enable == 0, outputs simply hold their previous value
    // (typical SRAM-style behavior -- no new read data driven this cycle)
}


