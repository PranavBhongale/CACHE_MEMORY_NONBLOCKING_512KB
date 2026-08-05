
`timescale 1ns/1ps

module top_l1_interface_tb ;

    parameter int ADDR_W        = 64;
    parameter int L1_LINE_BYTES = 32;
    parameter int L2_LINE_BYTES = 64;
    parameter int L1_LINE_BITS  = L1_LINE_BYTES * 8;
    parameter int L2_LINE_BITS  = L2_LINE_BYTES * 8;
    parameter int MSHR_ENTRIES  = 8;
    parameter int TAG_W         = 3;
    parameter int GTAG_W        = TAG_W + 1;

    parameter int REQ_DEPTH     = MSHR_ENTRIES;
    parameter int RESP_DEPTH    = MSHR_ENTRIES;


    logic clk ;
    logic rst_n ;

        // L1 Instruction Cache
    pkg::l2_req_t  i_req;
    logic          i_req_ready;

    pkg::l2_resp_t i_resp;
    logic          i_resp_ready;

    // L1 Data Cache
    pkg::l2_req_t  d_req;
    logic          d_req_ready;
    pkg::l2_resp_t d_resp;
    logic          d_resp_ready;

    // L2 Request Channel
    logic              l2_req_valid;
    pkg::l2_if_req_t   l2_req;
    logic              l2_req_ready;

    // L2 Response Channel
    logic              l2_resp_valid;
    pkg::l2_if_resp_t  l2_resp;
    logic              l2_resp_ready;




    // connection to the module
    L1_L2_TOP_INTERFACE #(
        .ADDR_W(ADDR_W),
        .L1_LINE_BYTES(L1_LINE_BYTES),
        .L2_LINE_BYTES(L2_LINE_BYTES),
        .L1_LINE_BITS(L1_LINE_BITS),
        .L2_LINE_BITS(L2_LINE_BITS),
        .MSHR_ENTRIES(MSHR_ENTRIES),
        .TAG_W(TAG_W),
        .GTAG_W(GTAG_W),

        .REQ_DEPTH(REQ_DEPTH),
        .RESP_DEPTH(RESP_DEPTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),

        // L1 Instruction Cache
        .i_req(i_req),
        .i_req_ready(i_req_ready),

        .i_resp(i_resp),
        .i_resp_ready(i_resp_ready),

        // L1 Data Cache
        .d_req(d_req),
        .d_req_ready(d_req_ready),

        .d_resp(d_resp),
        .d_resp_ready(d_resp_ready),

        // L2 Request Channel
        .l2_req_valid(l2_req_valid),
        .l2_req(l2_req),
        .l2_req_ready(l2_req_ready),

        // L2 Response Channel
        .l2_resp_valid(l2_resp_valid),
        .l2_resp(l2_resp),
        .l2_resp_ready(l2_resp_ready)
    );

  import "DPI-C" function void l1_l2_top_init();
  import "DPI-C" function void l1_l2_top_reset(input int rst);
  import "DPI-C" function void l1_l2_top_clock(input int clk);
  import "DPI-C" function void l1_l2_top_drive(
        input  pkg ::  l2_req_t i_req,
        input    logic  i_req_ready,
        output   pkg ::  l2_resp_t i_resp,
        output   logic  i_resp_ready,
        input    pkg ::  l2_req_t d_req,
        input    logic  d_req_ready,
        output   pkg ::  l2_resp_t d_resp,
        output   logic  d_resp_ready,

        // L2 facing port : this is the buffer interface to l2
        output   pkg ::  l2_if_req_t l2_req,
        output   logic  l2_req_valid,
        input    logic  l2_req_ready,

        input    pkg ::  l2_if_resp_t l2_resp,
        input    logic  l2_resp_valid,
        output   logic  l2_resp_ready
    );


    // clock generation  and give the same to golden system c model
    // to have synchronization between RTL and golden model
    initial begin
        rst_n = 0;
        l1_l2_top_init();
        #10
        rst_n = 1;
        clk = 0;
        forever  begin
            l1_l2_top_clock(int'(clk));
            #5 clk = ~clk;
        end
    end

    initial begin
        $dumpfile("top_l1_interface_tb.vcd");
        $dumpvars(0, top_l1_interface_tb);
    end


     // task for generating the transaction to the DUT and the golden model
     task automatic generate_transaction_for_i_cache();

            if (!rst_n) begin
                $display("Reset is asserted, cannot generate transaction");
                return;
            end
            if(!i_req_ready) begin
                $display("i_req_ready is not asserted, cannot generate transaction");
                return;
            end
            i_req.valid = 1'b1;

            i_req.op    = pkg::REQ_READ;  // For I-cache, we only generate read requests

            // Random 64-bit address (8-byte aligned)
            i_req.addr  = {$urandom(), $urandom()};
            i_req.addr[2:0] = 3'b000;

            // Random fields
            i_req.wdata = 0; // For I-cache, wdata is not used
            i_req.wmask = $urandom();
            i_req.tag   = 3'($urandom());

            @(posedge clk);
            i_req.valid = 1'b0;
     endtask

    // task for generating the transaction for Dcache
    task automatic generate_transaction_for_d_cache();

            if (!rst_n) begin
                $display("Reset is asserted, cannot generate transaction");
                return;
            end
            if(!d_req_ready) begin
                $display("d_req_ready is not asserted, cannot generate transaction");
                return;
            end
            d_req.valid = 1'b1;

            // Randomly choose between read and write-back operations
            if ($urandom_range(0, 1) == 0) begin
                d_req.op = pkg::REQ_READ;
            end else begin
                d_req.op = pkg::REQ_WRITE_BACK;
            end

            // Random 64-bit address (8-byte aligned)
            d_req.addr = {$urandom(), $urandom()};
            d_req.addr[2:0] = 3'b000;

            // Random fields

            d_req.wdata = {$urandom(), $urandom() , $urandom(), $urandom() , $urandom(), $urandom()
                            , $urandom(), $urandom()};
            d_req.wmask = $urandom();
            d_req.tag   = 3'($urandom());

            @(posedge clk);
            d_req.valid = 1'b0;
     endtask



     // task for checking the output of the DUT and the golden model
     task automatic check_output();
         // here i have to check the output of the DUT and the golden model
         // Implementation for checking output would go here



     endtask
    initial begin
        // Wait for reset to be deasserted
        @(negedge rst_n);
        @(posedge rst_n);

        // Generate transactions for I-cache and D-cache
        repeat (10) begin
            generate_transaction_for_i_cache();
            generate_transaction_for_d_cache();
            check_output();
            @(posedge clk);
        end

    end
    initial begin
        #5000
        $finish;
    end

    // l2_responce_function like memory 

    
endmodule
