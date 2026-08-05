`timescale 1ns/1ps

module LLC_interface #(
    parameter int LLC_ADDR_W      = 64,
    parameter int LLC_LINE_BYTES  = 64,
    parameter int LLC_LINE_BITS   = LLC_LINE_BYTES * 8,   //512
    parameter int L2_MSHR_ENTRIES = 8,
    parameter int LLC_TAG_W       = 3
)
(

    // Clock & Reset
    input  logic clk,
    input  logic rst_n,

    // L2 Side
    input  pkg::l2_llc_req_t   l2_req,
    output logic               l2_req_ready,

    output pkg::l2_llc_resp_t  l2_resp,
    input  logic               l2_resp_ready,

    // LLC Request Channel
    output logic                      llc_req_valid,
    output logic [LLC_ADDR_W-1:0]     llc_req_addr,
    output pkg::l2_llc_req_op_t       llc_req_op,
    output logic [LLC_TAG_W-1:0]      llc_req_tag,
    output logic [LLC_LINE_BITS-1:0]  llc_req_wdata,
    output logic [LLC_LINE_BYTES-1:0] llc_req_wmask,

    input  logic llc_req_ready,

    // LLC Response Channel
    input  logic                      llc_resp_valid,
    input  logic [LLC_TAG_W-1:0]      llc_resp_tag,
    input  pkg::l2_llc_resp_op_t      llc_resp_op,
    input  logic [LLC_LINE_BITS-1:0]  llc_resp_data,
    input  logic                      llc_resp_error,

    output logic llc_resp_ready
);

    // Forward L2 -> LLC
    always_comb begin

        llc_req_valid = 1'b0;
        llc_req_addr  = '0;
        llc_req_op    = pkg::LLC_REQ_READ;
        llc_req_tag   = '0;
        llc_req_wdata = '0;
        llc_req_wmask = '0;

        l2_req_ready  = 1'b0;

        if (rst_n) begin

            llc_req_valid = l2_req.valid;
            llc_req_addr  = l2_req.addr;
            llc_req_op    = l2_req.op;
            llc_req_tag   = l2_req.tag;
            llc_req_wdata = l2_req.wdata;
            llc_req_wmask = l2_req.wmask;

            l2_req_ready  = llc_req_ready;
        end
    end
    // Forward LLC -> L2
    always_comb begin

        l2_resp = '0;
        llc_resp_ready = 1'b0;

        if (rst_n) begin
            l2_resp.valid = llc_resp_valid;
            l2_resp.op    = llc_resp_op;
            l2_resp.tag   = llc_resp_tag;
            l2_resp.data  = llc_resp_data;
            l2_resp.error = llc_resp_error;
            llc_resp_ready = l2_resp_ready;
        end
    end
endmodule
