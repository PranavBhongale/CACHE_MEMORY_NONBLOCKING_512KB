`timescale 1ns/1ps
module cache_top_tb ;

    parameter int ADDR_W          = 64 ;
    parameter int L1_LINE_BYTES   = 32 ;
    parameter int L2_LINE_BYTES   = 64 ;
    parameter int MSHR_ENTRIES    = 8 ;
    parameter int TAG_W           = 3 ;
    parameter int LLC_ADDR_W      = 64 ;
    parameter int LLC_LINE_BYTES  = 64;
    parameter int L2_MSHR_ENTRIES = 8;
    parameter int LLC_TAG_W       = 3; // there is also MSHR at the side of LLC
    parameter int TM_TAG_BITS     = 47;
    parameter int MSHR_MAX_SEC    = 3 ;
    parameter int NUM_WAYS        = 4;

    // test-level knobs
    parameter int STALL_WARN_CYC    = 100;  // cycles to wait before flagging a handshake stall
    parameter int DRAIN_TIMEOUT_CYC = 3000; // default cycles wait_for_drain() will wait

    // connection to the cache memory

    logic clk ;
    logic rst_n ;

    logic cpu_req_valid ;
    pkg::l2_if_req_t cpu_req ;
    logic cpu_req_ready ;

    logic cpu_resp_valid ;
    logic cpu_resp_ready ;
    pkg :: l2_if_resp_t cpu_resp ;


    logic mem_req_valid ;  // output from cache //
    pkg :: l2_llc_req_t  mem_req ;
    logic mem_req_ready ; // input to  cache

    logic mem_resp_valid ; // input to cache
    pkg :: l2_llc_resp_t mem_resp ;
    logic mem_resp_ready  ;// output from cache.

    // ---------------- debug / scoreboard counters (auto-managed) ----------------
    int unsigned req_sent_cnt   = 0;
    int unsigned resp_recv_cnt  = 0;
    int unsigned mem_req_cnt    = 0;
    int unsigned mem_resp_cnt   = 0;
    int unsigned global_req_num = 0;
    logic        cpu_req_ready_prev ;

    // connection to DUT
     cache_top #(
     .ADDR_W (ADDR_W),
     .L1_LINE_BYTES(L1_LINE_BYTES),
     .L2_LINE_BYTES (L2_LINE_BYTES),
     .MSHR_ENTRIES (MSHR_ENTRIES),
     .TAG_W  (TAG_W),  // this are the MSHR tag_ form which MSHR entries does this data belong
     .LLC_ADDR_W (LLC_ADDR_W),
     .LLC_LINE_BYTES(LLC_LINE_BYTES),
     .L2_MSHR_ENTRIES(L2_MSHR_ENTRIES),
     .LLC_TAG_W(LLC_TAG_W), // there is also MSHR at the side of LLC
     .TM_TAG_BITS(TM_TAG_BITS),
     .MSHR_MAX_SEC (MSHR_MAX_SEC) ,
     .NUM_WAYS (NUM_WAYS)
     )dut(
    // clock and reset_n
    .clk(clk) ,
    .rst_n(rst_n) ,

    // cpu side L1 side
    .cpu_req_valid(cpu_req_valid) ,
    .cpu_req(cpu_req) ,
    .cpu_req_ready (cpu_req_ready),

    .cpu_resp(cpu_resp) ,
    .cpu_resp_valid(cpu_resp_valid) ,
    .cpu_resp_ready(cpu_resp_ready) ,

    // memory syde  LLC side
   .mem_req_valid (mem_req_valid),
   .mem_req (mem_req),
   .mem_req_ready(mem_req_ready) ,

   .mem_resp_valid(mem_resp_valid) ,
   .mem_resp(mem_resp) ,
   .mem_resp_ready(mem_resp_ready)

);

// connection to dummy memory
 dummy_llc #(
      .MEM_LINES (2048),
      .LINE_BITS (512),
      .ADDR_BITS (64),
      .TAG_BITS  (3),
      .RESP_LATENCY  ()
 ) dummey_memory (
       .clk(clk),
       .rst_n(rst_n),

    // Request from L2/MSHR
      .mem_req_valid(mem_req_valid),
      .mem_req_ready(mem_req_ready),
      .mem_req(mem_req),

    // Response to L2/MSHR
       .mem_resp_valid(mem_resp_valid),
       .mem_resp_ready(mem_resp_ready),
       .mem_resp(mem_resp)
);

// =====================================================================
// TASK LIBRARY
// =====================================================================

// ---- internal engine: one clean valid/ready handshake for a fully-
// formed request. Everything funnels through here — you normally don't
// call this directly, use send_req() / send_rand_req() below instead.
task automatic drive_request(input pkg :: l2_if_req_t req);
    int unsigned wait_cycles;
    int          req_num;
    begin
        req_num = global_req_num;
        global_req_num++;

        @(negedge clk);
        cpu_req_valid = 1'b1;
        cpu_req       = req ;
        $display("[%0t] >> Driving CPU REQ #%0d (addr=%0h tag=%0h), waiting for cpu_req_ready", $time, req_num, req.addr, req.gtag);
        display_l2_req(req);

        wait_cycles = 0;
        do begin
            @(posedge clk);
            wait_cycles++;
            if (wait_cycles == STALL_WARN_CYC) begin
                $display("[%0t] *** WARNING: CPU REQ #%0d has been waiting %0d cycles for cpu_req_ready — possible stall ***",
                          $time, req_num, wait_cycles);
                          $finish ;
            end
        end while (!cpu_req_ready);

        @(negedge clk);
        cpu_req_valid = 1'b0;
        req_sent_cnt++;
        $display("[%0t] << CPU REQ #%0d accepted after %0d cycle(s)", $time, req_num, wait_cycles);
    end
endtask

task automatic send_req(
    input logic [ADDR_W-1:0] addr,
    input bit                 is_write = 1'b0,
    input logic [TAG_W:0]   gtag      = '0,
    input logic                sub_sel  = 1'b0,
    input logic [255:0]       wdata    = '1,
    input logic [31:0]        wmask    = '1
);
    pkg :: l2_if_req_t req;
    begin
        req.op      = is_write ? pkg :: REQ_WRITE_BACK : pkg :: REQ_READ ;
        $display("req.op is " , req.op );
        req.addr    = addr;
        req.gtag     = gtag;
        req.sub_sel = sub_sel;
        req.wdata   = wdata;
        req.wmask   = wmask;
        drive_request(req);
    end
endtask

// ---- one request, every field randomized
task automatic send_rand_req();
    pkg :: l2_req_t req;
    begin
        req.valid   = 1'b1;
        req.op      = 1'($urandom()) ? pkg :: REQ_READ : pkg :: REQ_WRITE_BACK ;
        req.addr    = {$urandom() , $urandom()};
        req.tag     = TAG_W'($urandom_range(0 , 7));
        req.sub_sel = 1'($urandom_range(0, 1));
        req.wdata   = { $urandom(),  $urandom(),  $urandom(),  $urandom() , $urandom() , $urandom() , $urandom() , $urandom()};
        req.wmask   = $urandom();
        drive_request(req);
    end
endtask

// ---- n back-to-back requests to the SAME address — MSHR merge /
// secondary-miss stress (e.g. n = MSHR_MAX_SEC+2 to exceed the limit)
task automatic send_burst_same_addr(input logic [ADDR_W-1:0] addr, input int n, input bit is_write = 1'b0);
    begin
        $display("[%0t] -- burst: %0d back-to-back requests to SAME address %0h --", $time, n, addr);
        for (int i = 0; i < n; i++) begin
            send_req(addr, is_write, (TAG_W+1)'(i), i[0], {8{$urandom()}}, $urandom());
        end
    end
endtask

// ---- n back-to-back requests to n DISTINCT addresses, no idle gap —
// MSHR-full / queue backpressure stress (e.g. n = MSHR_ENTRIES+1)
task automatic send_burst_distinct(input int n, input bit is_write = 1'b0);
    begin
        $display("[%0t] -- burst: %0d back-to-back requests to DISTINCT addresses --", $time, n);
        for (int i = 0; i < n; i++) begin
            send_req({$urandom() ,$urandom()}, is_write , 4'(i), i[0], {8{$urandom()}}, $urandom());
        end
    end
endtask

// ---- just advance n clock edges
task automatic wait_clocks(input int n);
    begin
        repeat (n) @(posedge clk);
    end
endtask

// ---- drive rst_n through a clean reset, settle for 2 cycles after
task automatic reset_dut();
    begin
        rst_n = 0 ;
        $display("[%0t] Reset asserted (rst_n = 0)", $time);
        #20 ;
        rst_n = 1 ;
        $display("[%0t] Reset de-asserted (rst_n = 1)", $time);
        repeat (2) @(posedge clk);
    end
endtask

// ---- block until every sent request has a response, or timeout
task automatic wait_for_drain(input int timeout_cycles = DRAIN_TIMEOUT_CYC);
    begin
        fork
            begin : drain_wait
                wait (resp_recv_cnt == req_sent_cnt);
            end
            begin : drain_timeout
                repeat (timeout_cycles) @(posedge clk);
                $display("[%0t] *** WARNING: drain timeout (%0d cycles) hit with %0d/%0d responses received ***",
                           $time, timeout_cycles, resp_recv_cnt, req_sent_cnt);
            end
        join_any
        disable fork;
    end
endtask

// ---- dump the scoreboard + PASS/FAIL
task automatic print_summary();
    begin
        $display("========== SIMULATION SUMMARY ==========");
        $display("CPU requests sent      : %0d", req_sent_cnt);
        $display("CPU responses received : %0d", resp_recv_cnt);
        $display("LLC requests observed  : %0d", mem_req_cnt);
        $display("LLC responses observed : %0d", mem_resp_cnt);
        if (resp_recv_cnt == req_sent_cnt) begin
            $display("STATUS: PASS - every issued request got a response");
        end else begin
            $display("STATUS: FAIL - %0d request(s) missing a response", req_sent_cnt - resp_recv_cnt);
        end
        $display("==========================================");
    end
endtask

// ---- display helpers, used internally by drive_request() / the
// response-capture monitor below
task automatic display_l2_req(input pkg :: l2_if_req_t req);
    $display("========== L2 REQUEST [%0t] ==========", $time);
    if(req.op == pkg :: REQ_READ ) begin
         $display("op      = REQ_READ");
    end else begin $display("op      = REQ_WRITE_BACK"); end
    $display("tag     = %0h",  req.gtag);
    $display("sub_sel = %0b",  req.sub_sel);
    $display("data    = %0h",  req.wdata);
    $display("wmask   = %0b",  req.wmask);
    $display("address =  %0h" , req.addr);
    $display("=================================");
endtask

task automatic display_l2_resp(input pkg :: l2_if_resp_t resp);
    $display("========== L2 RESPONSE [%0t] ==========", $time);
    if(resp.op == pkg :: RESP_FILL ) begin
        $display("op      = RESP_FILL"); end
    else begin $display("op      = RESP_WB_ACK"); end
    $display("tag     = %0h",  resp.gtag);
    $display("sub_sel = %0b",  resp.sub_sel);
    $display("data    = %0h",  resp.data);
    $display("error   = %0b",  resp.error);
    if (resp.error) begin
        $display("*** WARNING: response #%0d flagged error=1 ***", resp_recv_cnt + 1);
    end
    $display("=================================");
endtask

// =====================================================================
// BACKGROUND MONITORS — run automatically, no task calls needed
// =====================================================================

// CPU response capture — catches every response, not just the first
initial begin
    cpu_resp_ready = 1'b1;
end

always @(posedge clk) begin
    if (rst_n && cpu_resp_valid && cpu_resp_ready) begin
        resp_recv_cnt++;
        $display("[%0t] << CPU RESP #%0d captured", $time, resp_recv_cnt);
        display_l2_resp(cpu_resp);
    end
end

// LLC-side traffic monitor — uses %p since l2_llc_req_t / l2_llc_resp_t
// field layout isn't known here; say the word and I'll break it out
// field-by-field like the CPU-side tasks above.
always @(posedge clk) begin
    if (rst_n && mem_req_valid && mem_req_ready) begin
        mem_req_cnt++;
        $display("[%0t] ---- LLC REQ  #%0d : %p", $time, mem_req_cnt, mem_req);
    end
    if (rst_n && mem_resp_valid && mem_resp_ready) begin
        mem_resp_cnt++;
        $display("[%0t] ---- LLC RESP #%0d : %p", $time, mem_resp_cnt, mem_resp);
    end
end

// backpressure edge-detect — flags exactly when cpu_req_ready drops
always @(posedge clk) begin
    if (!rst_n) begin
        cpu_req_ready_prev <= 1'b0;
    end else begin
        if (cpu_req_ready_prev && !cpu_req_ready) begin
            $display("[%0t] -- BACKPRESSURE: cpu_req_ready deasserted (structural hazard / MSHR or queue full) --", $time);
        end
        cpu_req_ready_prev <= cpu_req_ready;
    end
end

// clock gen
initial begin
    clk = 0 ;
    forever begin
        clk = ~clk ;
        #5;
    end
end

initial begin
    $dumpfile("top.vcd");
    $dumpvars(0 , cache_top_tb);
end

initial begin
    reset_dut();

//     for(int i = 0 ; i <= 10 ; i ++ ) begin
//     send_req(
//     .addr     (64'hffffffffffffffff),
//     .is_write (1'b0),
//     .gtag      (4'b0001),
//     .sub_sel  (1'b0),
//     .wdata    ('1),
//     .wmask    ('1)
// );
// end

// for(int i = 0 ; i <= 10 ; i ++ ) begin
//     send_req(
//     .addr     (64'hfffffff1ffff1fff),
//     .is_write (1'b0),
//     .gtag      (4'b0001),
//     .sub_sel  (1'b0),
//     .wdata    ('1),
//     .wmask    ('1)
// );
// end

for(int i = 0 ; i <= 10 ; i ++ ) begin
    send_req(
    .addr     ((64'h1ffffff1ffff1f1f + 64'(i*64))),
    .is_write (1'b0),
    .gtag      (4'b0001),
    .sub_sel  (1'b0),
    .wdata    ('1),
    .wmask    ('1)
);
end


    wait_for_drain();
    print_summary();
    $display("simulation finish ");
    $finish;
end



endmodule
