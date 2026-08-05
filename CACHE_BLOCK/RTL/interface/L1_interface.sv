`timescale 1ns/1ps

module L1_interface #(
    parameter int ADDR_W        = 64,
    parameter int L1_LINE_BYTES = 32,
    parameter int L2_LINE_BYTES = 64,
    parameter int L1_LINE_BITS  = L1_LINE_BYTES * 8,
    parameter int L2_LINE_BITS  = L2_LINE_BYTES * 8,
    parameter int MSHR_ENTRIES  = 8,
    parameter int TAG_W         = 3,
    parameter int GTAG_W        = TAG_W + 1
)(
    // Clock / Reset
    input  logic clk,
    input  logic rst_n,

    // L1 Instruction Cache Interface
    input  pkg::l2_req_t  i_req, // request from L1 instruction cache memory
    output logic          i_req_ready, // IF l2 is ready then we have to accept the data

    output pkg::l2_resp_t i_resp, // same for this
    input  logic          i_resp_ready,  //valid ready handsake


    // L1 Data Cache Interface
    input  pkg::l2_req_t  d_req, // request from data cache
    output logic          d_req_ready, // L2 is ready then request come


    output pkg::l2_resp_t d_resp, // responce to the l1_data memory
    input  logic          d_resp_ready, // give responce when ready is there

    // L2 Request Channel
    output logic               l2_req_valid,
    output pkg::l2_if_req_t    l2_req,
    input  logic               l2_req_ready,


    // L2 Response Channel
    input  logic               l2_resp_valid,
    input  pkg::l2_if_resp_t   l2_resp,
    output logic               l2_resp_ready
);


    // Request Arbitration
    // Fixed Priority:
    //      I$ > D$

    always_comb begin

        l2_req_valid = 1'b0;
        l2_req       = '0;

        i_req_ready  = 1'b0;
        d_req_ready  = 1'b0;

        if (rst_n) begin

            // Instruction Cache Wins
            if (i_req.valid) begin

                l2_req_valid   = 1'b1;

                l2_req.op      = i_req.op;
                l2_req.addr    = i_req.addr;
                l2_req.gtag    = {i_req.tag,1'b0};   // source = I$ //cancatination
                l2_req.sub_sel = i_req.sub_sel;
                l2_req.wdata   = i_req.wdata;
                l2_req.wmask   = i_req.wmask;

                i_req_ready    = l2_req_ready;

            end

            // Otherwise Data Cache
            else if (d_req.valid) begin

                l2_req_valid   = 1'b1;

                l2_req.op      = d_req.op;
                l2_req.addr    = d_req.addr;
                l2_req.gtag    = {d_req.tag,1'b1};   // source = D$
                l2_req.sub_sel = d_req.sub_sel;
                l2_req.wdata   = d_req.wdata;
                l2_req.wmask   = d_req.wmask;

                d_req_ready    = l2_req_ready;

            end
        end
    end

    // Response Routing
    always_comb begin

        i_resp = '0;
        d_resp = '0;

        l2_resp_ready = 1'b0;

        if (rst_n) begin

            if (l2_resp_valid) begin

                // Source = D$
                if (l2_resp.gtag[0]) begin

                    d_resp.valid   = 1'b1;
                    d_resp.op      = l2_resp.op;
                    d_resp.tag     = l2_resp.gtag[GTAG_W-1:1];
                    d_resp.sub_sel = l2_resp.sub_sel;
                    d_resp.data    = l2_resp.data;
                    d_resp.error   = l2_resp.error;

                    l2_resp_ready  = d_resp_ready;

                end

                // Source = I$
                else begin

                    i_resp.valid   = 1'b1;
                    i_resp.op      = l2_resp.op;
                    i_resp.tag     = l2_resp.gtag[GTAG_W-1:1];
                    i_resp.sub_sel = l2_resp.sub_sel;
                    i_resp.data    = l2_resp.data;
                    i_resp.error   = l2_resp.error;

                    l2_resp_ready  = i_resp_ready;

                end
            end
        end
    end

endmodule

