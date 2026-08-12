`timescale 1ns/1ps

module cache_top_tb ;


    parameter int ADDR_W = 64 ;
    parameter int L1_LINE_BYTES = 32 ;
    parameter int L2_LINE_BYTES = 64 ;
    parameter int MSHR_ENTRIES = 8 ;
    parameter int TAG_W = 3 ;
    parameter int LLC_ADDR_W = 64 ;
    parameter int LLC_LINE_BYTES = 64;
    parameter int L2_MSHR_ENTRIES = 8;
    parameter int LLC_TAG_W    = 3; // there is also MSHR at the side of LLC
    parameter int TM_TAG_BITS = 47;
    parameter int MSHR_MAX_SEC = 3 ;
    parameter int NUM_WAYS = 4;

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
    pkg :: l2_llc_resp_t  mem_req ;
    logic mem_req_ready ; // input to  cache

    logic mem_resp_valid ; // input to cache
    pkg :: l2_llc_resp_t mem_resp ;
    logic mem_resp_ready  ;// output from cache.


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









endmodule

