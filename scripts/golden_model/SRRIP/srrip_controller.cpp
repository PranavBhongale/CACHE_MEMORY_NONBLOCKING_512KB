// srrip_controller.cpp
#include "srrip_controller_interface.h"
#include<systemc.h> 
#include<iostream>

void srrip_controller::do_srrip() {
 //  some debugging
 std::cout << "do_srrip() called at "
          << sc_time_stamp() << std::endl;
    std::cout << "--------------------------------\n";
    std::cout << "Time = " << sc_time_stamp() << "\n";
    std::cout << "req_valid = " << req_valid.read() << "\n";
    std::cout << "index     = " << index.read() << "\n";
    std::cout << "hit       = " << hit.read() << "\n";
    std::cout << "hit_way   = " << hit_way.read() << "\n";
    std::cout << "rst_n     = " << rst_n.read() << std::endl;
    //  synchronous reset 
    if (rst_n.read() == false) {
        for (unsigned s = 0; s < NUM_SETS; s++)
            for (unsigned w = 0; w < NUM_WAYS; w++)
                rrpv_table[s][w] = RRPV_MAX;

        victim_way.write(0);
        victim_valid.write(false);
        return;
    }

    if (!req_valid.read()) {
        victim_valid.write(false);
        return;
    }

    unsigned idx = index.read().to_uint();


    // HIT PATH: promote the touched line to "near-immediate" reuse
    if (hit.read()) {
        unsigned hw = hit_way.read().to_uint();
        rrpv_table[idx][hw] = RRPV_NEAR;      // RRPV = 0

        victim_valid.write(false);
        victim_way.write(0);                  // don't-care on hit
        return;
    }

    // MISS PATH: SRRIP victim search + age + insert
    //   1. find current max RRPV in the set
    //   2. age (increment) every way by (RRPV_MAX - max) in one shot
    //      -> this is the hardware-equivalent of "keep incrementing
    //         all counters until someone hits RRPV_MAX", done combinationally
    //   3. victim = first (lowest-index) way whose aged RRPV == RRPV_MAX
    //   4. install new line: victim's RRPV <- RRPV_LONG (2)
    unsigned max_rrpv = 0;
    for (unsigned w = 0; w < NUM_WAYS; w++) {
        unsigned v = rrpv_table[idx][w].to_uint();
        if (v > max_rrpv) max_rrpv = v;
    }

    unsigned delta = RRPV_MAX - max_rrpv;      // 0 if some way already at MAX
    unsigned victim = 0;
    bool     found  = false;

    for (unsigned w = 0; w < NUM_WAYS; w++) {
        unsigned aged = rrpv_table[idx][w].to_uint() + delta;   // no overflow: <= RRPV_MAX by construction
        rrpv_table[idx][w] = (sc_uint<RRPV_BITS>) aged;

        if (!found && aged == RRPV_MAX) {
            victim = w;
            found  = true;
        }
    }

    // install the incoming line at the victim way with the SRRIP long-interval value
    rrpv_table[idx][victim] = RRPV_LONG;

    victim_way.write(victim);
    victim_valid.write(true);


}
