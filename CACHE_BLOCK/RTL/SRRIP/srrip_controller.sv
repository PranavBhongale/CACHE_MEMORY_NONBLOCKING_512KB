`timescale 1ns/1ps
module srrip_controller #(
    parameter  int NUM_SETS   = 2048,
    parameter  int NUM_WAYS   = 4,
    parameter  int INDEX_BITS = 11,
    parameter  int WAY_BITS   = $clog2(NUM_WAYS)
) (
    input  logic                  clk,
    input  logic                  rst_n,        // active-low sync reset

    input  logic                  req_valid,    // a lookup is happening this cycle
    input  logic [INDEX_BITS-1:0] index,        // set index
    input  logic                  hit,          // 1 = hit, 0 = miss
    input  logic [WAY_BITS-1:0]   hit_way,      // valid only when hit==1 (0 on miss, per spec)

    output logic [WAY_BITS-1:0]   victim_way,   // valid only when hit==0 (the way to evict/fill)
    output logic                  victim_valid
);

    localparam int RrpvBits = 2;
    localparam logic [RrpvBits-1:0] RrpvMax  = 2'd3;  // "distant"  (never used again soon)
    localparam logic [RrpvBits-1:0] RrpvLong = 2'd2;  // SRRIP insertion value (long re-ref interval)
    localparam logic [RrpvBits-1:0] RrpvNear = 2'd0;  // set on hit (near-immediate re-reference)

    logic [RrpvBits-1:0] rrpv_table [NUM_SETS][NUM_WAYS];
    logic [RrpvBits-1:0] max_rrpv;
    logic [RrpvBits-1:0] delta;
    logic [RrpvBits-1:0] aged        [NUM_WAYS];   // this set's row after aging
    logic [WAY_BITS-1:0] victim_nxt;
    logic                found;

     always_comb begin
        max_rrpv   = '0;
        delta      = RrpvMax;
        victim_nxt = '0;
        found      = 1'b0;
        for (int w = 0; w < NUM_WAYS; w++)
            aged[w] = rrpv_table[index][w];   // default: unchanged

        if (req_valid && !hit) begin
            for (int w = 0; w < NUM_WAYS; w++)
                if (rrpv_table[index][w] > max_rrpv)
                    max_rrpv = rrpv_table[index][w];

            delta = RrpvMax - max_rrpv;

            for (int w = 0; w < NUM_WAYS; w++) begin
                aged[w] = rrpv_table[index][w] + delta;
                if (!found && aged[w] == RrpvMax) begin
                    victim_nxt = w[WAY_BITS-1:0];
                    found      = 1'b1;
                end
            end
        end
    end

    always_ff @(posedge clk) begin : srrip
        if (!rst_n) begin
            /* verilator lint_off BLKSEQ */
            for (int idx = 0; idx < NUM_SETS*NUM_WAYS; idx++) // this is also a way to make double
                rrpv_table[idx / NUM_WAYS][idx % NUM_WAYS] = RrpvMax; // for loop
            /* verilator lint_on BLKSEQ */

            victim_way   <= '0;
            victim_valid <= 1'b0;

        end else if (!req_valid) begin // do every thing when request is valid
            // no lookup this cycle  hold the table, just drop victim_valid
            victim_valid <= 1'b0;

        end else if (hit) begin
            rrpv_table[index][hit_way] <= RrpvNear;
            victim_valid <= 1'b0;
            victim_way   <= '0;              // don't-care on hit, per spec

        end else begin
            for (int w = 0; w < NUM_WAYS; w++)
                rrpv_table[index][w] <= aged[w];
            rrpv_table[index][victim_nxt] <= RrpvLong;   // overrides aged[victim_nxt] above

            victim_way   <= victim_nxt;
            victim_valid <= 1'b1;
        end
    end

endmodule
