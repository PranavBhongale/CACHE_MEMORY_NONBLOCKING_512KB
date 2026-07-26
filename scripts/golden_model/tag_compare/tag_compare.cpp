// tag_compare.cpp
#include "tag_compare_top.h"

void tag_compare::do_compare() {

    sc_uint<TC_TAG_BITS> t[TC_NUM_WAYS];
    t[0] = tag_way0.read();
    t[1] = tag_way1.read();
    t[2] = tag_way2.read();
    t[3] = tag_way3.read();

    sc_uint<TC_NUM_WAYS> vbits = tag_valid.read();
    sc_uint<TC_TAG_BITS> rtag  = req_tag.read();

    bool     found       = false;
    unsigned matched_way  = 0;

    // 4 parallel equality checks (real hardware: 4 independent comparators,
    // all evaluated at once -- this loop just models that in software).
    // Priority-encode: lowest way index wins if more than one somehow
    // matches (shouldn't happen in a correctly maintained cache, but
    // keeps behavior well-defined instead of ambiguous).
    for (unsigned w = 0; w < TC_NUM_WAYS; w++) {
        bool way_valid = vbits[w];
        bool way_match = (t[w] == rtag);

        if (!found && way_valid && way_match) {
            found       = true;
            matched_way = w;
        }
    }

    hit.write(found);
    miss.write(!found);
    hit_way.write(found ? matched_way : 0);
}

