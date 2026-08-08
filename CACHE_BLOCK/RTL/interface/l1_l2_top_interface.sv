`timescale 1ns/1ps


module l1_l2_top_interface #(
    parameter int ADDR_W        = 64,
    parameter int L1_LINE_BYTES = 32,
    parameter int L2_LINE_BYTES = 64,
    parameter int L1_LINE_BITS  = L1_LINE_BYTES * 8,
    parameter int L2_LINE_BITS  = L2_LINE_BYTES * 8,
    parameter int MSHR_ENTRIES  = 8,
    parameter int TAG_W         = 3,
    parameter int GTAG_W        = TAG_W + 1,

    parameter int REQ_DEPTH     = MSHR_ENTRIES,
    parameter int RESP_DEPTH    = MSHR_ENTRIES
)(
    // Clock / Reset
    input logic clk,
    input logic rst_n,

    // L1 Instruction Cache
    input  pkg::l2_req_t  i_req,
    output logic          i_req_ready,

    output pkg::l2_resp_t i_resp,
    input  logic          i_resp_ready,

    // L1 Data Cache
    input  pkg::l2_req_t  d_req,
    output logic          d_req_ready,

    output pkg::l2_resp_t d_resp,
    input  logic          d_resp_ready,

    // L2 Request Channel
    output logic              l2_req_valid,
    output pkg::l2_if_req_t   l2_req,
    input  logic              l2_req_ready,

    // L2 Response Channel
    input  logic              l2_resp_valid,
    input  pkg::l2_if_resp_t  l2_resp,
    output logic              l2_resp_ready
);

    // Internal Signals

    // Arbiter -> Request FIFO
    logic             arb_req_valid;
    logic             arb_req_ready;
    pkg::l2_if_req_t  arb_req_data;

    // Response FIFO -> Arbiter
    logic              fifo_resp_valid;
    logic              fifo_resp_ready;
    pkg::l2_if_resp_t  fifo_resp_data;



    // L1 Interface / Arbiter
    L1_interface #(
        .ADDR_W(ADDR_W),
        .L1_LINE_BYTES(L1_LINE_BYTES),
        .L2_LINE_BYTES(L2_LINE_BYTES),
        .L1_LINE_BITS(L1_LINE_BITS),
        .L2_LINE_BITS(L2_LINE_BITS),
        .MSHR_ENTRIES(MSHR_ENTRIES),
        .TAG_W(TAG_W),
        .GTAG_W(GTAG_W)
    ) arb (
        .clk(clk),
        .rst_n(rst_n),

        .i_req(i_req),
        .i_req_ready(i_req_ready),
        .i_resp(i_resp),
        .i_resp_ready(i_resp_ready),

        .d_req(d_req),
        .d_req_ready(d_req_ready),
        .d_resp(d_resp),
        .d_resp_ready(d_resp_ready),

        .l2_req_valid(arb_req_valid),
        .l2_req(arb_req_data),
        .l2_req_ready(arb_req_ready),

        .l2_resp_valid(fifo_resp_valid),
        .l2_resp(fifo_resp_data),
        .l2_resp_ready(fifo_resp_ready)
    );

    // Request FIFO
    buffer #(
        .T(pkg::l2_if_req_t),
        .DEPTH(REQ_DEPTH)
    ) req_fifo (

        .clk(clk),
        .rst_n(rst_n),

        .in_valid(arb_req_valid),
        .in_data(arb_req_data),
        .in_ready(arb_req_ready),

        .out_valid(l2_req_valid),
        .out_data(l2_req),
        .out_ready(l2_req_ready)
    );

    // Response FIFO

    buffer #(
        .T(pkg::l2_if_resp_t),
        .DEPTH(RESP_DEPTH)
    ) resp_fifo (

        .clk(clk),
        .rst_n(rst_n),

        .in_valid(l2_resp_valid),
        .in_data(l2_resp),
        .in_ready(l2_resp_ready),

        .out_valid(fifo_resp_valid),
        .out_data(fifo_resp_data),
        .out_ready(fifo_resp_ready)
    );

endmodule
