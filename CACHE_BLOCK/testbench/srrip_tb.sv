// srrip test bench
`timescale 1ns/1ps

module srrip_tb;

    // Parameters (must be declared before any signal that sizes off them)
    parameter int NUM_SETS   = 2048;
    parameter int NUM_WAYS   = 4;
    parameter int INDEX_BITS = 11;
    parameter int WAY_BITS   = $clog2(NUM_WAYS);

    // DUT signals
    logic                  clk = 1'b0;   // initialize here, not mid-testbench
    logic                  rst_n;        // active-low sync reset

    logic                  req_valid;    // a lookup is happening this cycle
    logic [INDEX_BITS-1:0] index;        // set index
    logic                  hit;          // 1 = hit, 0 = miss
    logic [WAY_BITS-1:0]   hit_way;      // valid only when hit==1 (0 on miss, per spec)

    logic [WAY_BITS-1:0]   victim_way;   // valid only when hit==0 (the way to evict/fill)
    logic                  victim_valid;

    // DPI-C imports (golden model)
    import "DPI-C" function void rrip_init();
    import "DPI-C" function void rrip_reset(input int rst);
    import "DPI-C" function void rrip_clock(input int clk);          // the ONLY thing that clocks the golden model
    import "DPI-C" function void rrip_drive(                          // apply inputs mid-cycle, no output read
        input int req_valid,
        input int index,
        input int hit,
        input int hit_way
    );
    import "DPI-C" function void rrip_sample(                         // read outputs after the golden model's own posedge
        output int victim_way,
        output int victim_valid
    );
    import "DPI-C" function void rrip_finish();

    int victim_way_golden;
    int victim_valid_golden;

    // DUT instantiation
    srrip_controller #(
        .NUM_SETS  (NUM_SETS),
        .NUM_WAYS  (NUM_WAYS),
        .INDEX_BITS(INDEX_BITS),
        .WAY_BITS  (WAY_BITS)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),

        .req_valid   (req_valid),
        .index       (index),
        .hit         (hit),
        .hit_way     (hit_way),

        .victim_way  (victim_way),
        .victim_valid(victim_valid)
    );

    // Clock generation — the single source of truth for the golden
    // model's clock. rrip_drive/rrip_sample never toggle it themselves.
    initial begin
        forever begin
            #5 clk = ~clk;
            rrip_clock(int'(clk));
        end
    end

    // Reset task — synchronized to the clock, not a raw #delay
    task automatic reset();
        rst_n = 0;
        rrip_reset(0);
        repeat (2) @(negedge clk);
        rrip_reset(1);
        rst_n = 1;
    endtask

    // Drive one transaction and check DUT vs golden model
    task automatic send_transaction(
        input int req,
        input int idx,
        input int hit_i,
        input int way
    );
        begin
            @(negedge clk);   // drive inputs mid-cycle, clear of the sampling edge
            req_valid = (req == 1);
            index     = INDEX_BITS'(idx);
            hit       = (hit_i == 1);
            hit_way   = WAY_BITS'(way);

            rrip_drive(req, idx, hit_i, way);   // same inputs into the golden model

            @(posedge clk);   // rrip_clock(1) already fired here for both RTL and golden model

            rrip_sample(victim_way_golden, victim_valid_golden);   // now safe to read

            // victim_way / victim_valid are only meaningful on a miss (per spec)
            if (hit_i == 0 &&
                (victim_way   !== WAY_BITS'(victim_way_golden) ||
                 victim_valid !== 1'(victim_valid_golden))) begin
                $display("--------------------------------");
                $display("req_valid = %0d", req_valid);
                $display("index     = %0d", index);
                $display("hit       = %0d", hit);
                $display("hit_way   = %0d", hit_way);

                $display("RTL victim_way    = %0d", victim_way);
                $display("SC  victim_way    = %0d", victim_way_golden);

                $display("RTL victim_valid  = %0d", victim_valid);
                $display("SC  victim_valid  = %0d", victim_valid_golden);
                $error("Mismatch!");
            end
        end
    endtask


    // Test sequence
    initial begin
        rrip_init();
        reset();

        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);
        send_transaction(1, 0, 0, 0);

        repeat(20)
           send_transaction(1,0,1,0);

        send_transaction(1,0,1,0);
        send_transaction(1,0,1,1);
        send_transaction(1,0,1,2);
        send_transaction(1,0,1,3);



        send_transaction(1,0,0,0);
        send_transaction(1,0,1,0);
        send_transaction(1,0,0,0);
        send_transaction(1,0,1,1);
        send_transaction(1,0,0,0);
        send_transaction(1,0,1,2);
        send_transaction(1,0,0,0);
        send_transaction(1,0,1,3);

        send_transaction(1,0,0,0);

        send_transaction(1,1,0,0);

        send_transaction(1,5,0,0);

        send_transaction(1,1024,0,0);

        send_transaction(1,2047,0,0);

        send_transaction(0,0,0,0);
        send_transaction(0,0,0,0);
        send_transaction(1,0,0,0);
        send_transaction(0,0,0,0);

        send_transaction(1,0,0,0);

        send_transaction(1,2047,0,0);

        send_transaction(1,1023,0,0);

        send_transaction(1,1024,0,0);

        repeat(1000) begin
    send_transaction(
        $urandom_range(0,1),
        $urandom_range(0,2047),
        $urandom_range(0,1),
        $urandom_range(0,3)
    );
end
       repeat(100)
          send_transaction(1,0,0,0);
     @(negedge clk);
        req_valid = 1'b0;   // go idle so the rest of the run isn't a phantom hit storm
    end

    // flush/report the golden model at end of run
    final begin
        rrip_finish();
    end

    // stop the simulation after some time
    initial begin
        #50000;
        $finish;
    end

    initial begin
        $dumpfile("srrip_tb.vcd");
        $dumpvars(0, srrip_tb);
    end

endmodule
