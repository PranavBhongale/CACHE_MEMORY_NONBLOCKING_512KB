`timescale 1ns/1ps

module global_control #(
    parameter int ADDR_W          = 64,
    parameter int L1_LINE_BYTES   = 32,
    parameter int L2_LINE_BYTES   = 64,
    parameter int L1_LINE_BITS    = L1_LINE_BYTES * 8,
    parameter int L2_LINE_BITS    = L2_LINE_BYTES * 8,
    parameter int MSHR_ENTRIES    = 8,
    parameter int TAG_W           = 3,
    parameter int GTAG_W          = TAG_W + 1,
    // REQUEST / RESPONSE QUEUES

    parameter int REQ_DEPTH       = MSHR_ENTRIES,
    parameter int RESP_DEPTH      = MSHR_ENTRIES,

    // LLC PARAMETERS
    parameter int LLC_ADDR_W      = 64,
    parameter int LLC_LINE_BYTES  = 64,
    parameter int LLC_LINE_BITS   = LLC_LINE_BYTES * 8,
    parameter int L2_MSHR_ENTRIES = 8,
    parameter int LLC_TAG_W       = 3,

    // TAG MEMORY PARAMETERS
    parameter int TM_NUM_SETS     = 2048,
    parameter int TM_NUM_WAYS     = 4,
    parameter int TM_INDEX_BITS   = 11,
    parameter int TM_TAG_BITS     = 47,
    parameter int TC_TAG_BITS     = TM_TAG_BITS,
    parameter int INDEX_BITS      = TM_INDEX_BITS,
    parameter int LINE_BITS       = L2_LINE_BITS,
    parameter int MSHR_MAX_SEC    = 3

) (
    // CLOCK AND RESET
    input  logic clk,
    input logic rst_n,
    // UPSTREAM / L1 FACING PORT
    input  logic              l2_req_valid,
    input  pkg::l2_if_req_t   l2_req,
    output logic              l2_req_ready,

    output logic              l2_resp_valid,
    output pkg::l2_if_resp_t  l2_resp,
    input  logic              l2_resp_ready,
    // TAG MEMORY PORT
    output logic                       tm_read_enable,
    output logic [TM_INDEX_BITS-1:0]   tm_index,
    input logic [TM_TAG_BITS-1:0]      tm_tag_way0,
    input logic [TM_TAG_BITS-1:0]      tm_tag_way1,
    input logic [TM_TAG_BITS-1:0]      tm_tag_way2,
    input logic [TM_TAG_BITS-1:0]      tm_tag_way3,
    input logic [TM_NUM_WAYS-1:0]      tm_tag_valid,

    // TAG MEMORY WRITE
    output logic                       tm_write_enable,
    output logic [1:0]                 tm_write_way,
    output logic [TM_TAG_BITS-1:0]     tm_tag_in,
    output logic                       tm_valid_in,

    // TAG COMPARE PORT
    output logic [TC_TAG_BITS-1:0]     tc_req_tag,
    input logic                        tc_hit,
    input logic                        tc_miss,
    input logic [1:0]                  tc_hit_way,

    // SRRIP REPLACEMENT CONTROLLER
    output logic                       sr_req_valid,
    output logic [INDEX_BITS-1:0]      sr_index,
    output logic                       sr_hit,
    output logic [1:0]                 sr_hit_way,
    input logic [1:0]                  sr_victim_way,
    input logic                        sr_victim_valid,

    // DATA ARRAY READ PORT
    output logic                       da_rd_en,
    output logic [INDEX_BITS-1:0]      da_rd_set,
    output logic [1:0]                 da_rd_way,
    input logic [LINE_BITS-1:0]        da_rd_data,
    input logic                        da_rd_valid,
    input logic                        da_rd_dirty,

    // DATA ARRAY WRITE PORT
    output logic                       da_wr_en,
    output logic [INDEX_BITS-1:0]      da_wr_set,
    output logic [1:0]                 da_wr_way,
    output logic [LINE_BITS-1:0]        da_wr_data,
    output logic                       da_wr_valid,
    output logic                       da_wr_dirty,

    // MSHR TABLE
    // ALLOCATION / SECONDARY MERGE PORT
    output logic                       mshr_alloc_req,
    output logic [TM_INDEX_BITS-1:0]   mshr_alloc_index,
    output logic [TM_TAG_BITS-1:0]     mshr_alloc_tag,
    output logic [1:0]                 mshr_alloc_way,
    output logic                       mshr_alloc_victim_dirty,
    output logic [TM_TAG_BITS-1:0]     mshr_alloc_victim_tag,
    output logic [LINE_BITS-1:0]       mshr_alloc_victim_data,
    output logic [GTAG_W-1:0]          mshr_alloc_gtag,
    output pkg::req_op_t               mshr_alloc_op,
    output logic                       mshr_alloc_sub_sel,
    output logic [L1_LINE_BITS-1:0]    mshr_alloc_wdata,
    output logic [L1_LINE_BYTES-1:0]   mshr_alloc_wmask,

    // MSHR ALLOCATION RESPONSE
    input logic                        mshr_alloc_ready,
    input logic                        mshr_alloc_secondary_hit,
    input logic                        mshr_alloc_full_and_write_conflict,

    // MSHR TABLE
    // FILL COMMIT PORT
    input logic                        mshr_commit_valid,
    input logic [TM_INDEX_BITS-1:0]    mshr_commit_index,
    input logic [1:0]                  mshr_commit_way,
    input logic [TM_TAG_BITS-1:0]      mshr_commit_tag,
    input logic [LINE_BITS-1:0]        mshr_commit_data,
    input logic                        mshr_commit_dirty,


    // MSHR RESPONSE PORT
    // MSHR -> Global Control -> L1
    // Global control arbitrates the response.
    input logic                        mshr_resp_valid,
    input pkg::l2_if_resp_t            mshr_resp,
    output logic                       mshr_resp_ready

);

pkg :: gc_state_t current_state  , next_state  ;

pkg :: gc_request_t cur ;
always_ff @(posedge clk ) begin

    if(!rst_n) begin
        current_state <= pkg::  GC_IDLE;
    end else
        current_state <= next_state;
end



int base = cur.req.sub_sel ? L1_LINE_BITS : 0;
always_comb begin

    // difault values  to avoid latch
    tm_read_enable = 0 ;
    tm_index = 0 ;
    tm_write_enable  = 0 ;
    tm_write_way = 0 ;
    tm_tag_in = 0 ;
    tm_valid_in = 0 ;


    // for SRRIP and data array ;
    sr_req_valid = 0 ;
    sr_hit = 0 ;
    sr_hit_way = 0;
    da_rd_en = 0 ;
    da_rd_set = 0 ;
    da_rd_way = 0 ;
    da_wr_en = 0 ;
    da_wr_set = 0 ;
    da_wr_way = 0 ;
    da_wr_data = 0 ;
    da_wr_valid = 0 ;
    da_wr_dirty = 0 ;

    mshr_alloc_req = 0 ;


    if(!rst_n)begin
     cur.valid = 1'b0 ;

     l2_req_ready = 1'b0;
     l2_resp_valid = 0 ;
     l2_resp = '0;

     tm_read_enable = 0 ;
     tm_index = 0 ;
     tm_write_enable = 0 ;
     tm_write_way = 0 ;
     tm_tag_in = 0 ;
     tm_valid_in = 0 ;

     tc_req_tag = 0 ;

     sr_req_valid = 0 ;
     sr_index = 0 ;
     sr_hit = 0 ;
     sr_hit_way = 0 ;

     da_rd_en = 0 ;
     da_rd_set = 0 ;
     da_rd_way = 0 ;
     da_wr_en = 0 ;
     da_wr_set = 0 ;
     da_wr_way = 0 ;
     da_wr_data = 0 ;
     da_wr_valid = 0 ;
     da_wr_dirty = 0 ;

     mshr_alloc_req = 0 ;
     mshr_resp_ready = 0 ;

    end else begin


      if (mshr_commit_valid) begin

        tm_write_enable = 1 ;
        tm_index = mshr_commit_index ;
        tm_write_way = mshr_commit_way ;
        tm_tag_in =  mshr_commit_tag ;
        tm_valid_in = 1 ;

        da_wr_en = 1 ;
        da_wr_set = mshr_commit_index ;
        da_wr_way = mshr_commit_way ;
        da_wr_data = mshr_commit_data ;
        da_wr_dirty = mshr_commit_dirty ;
      end

      //  responce arbitration ---

      if(mshr_resp_valid)begin
        l2_resp_valid = 1 ;
        l2_resp = mshr_resp ;
        mshr_resp_ready = l2_resp_ready ;
      end else begin
         mshr_resp_ready = 0 ;
      end



    //   MAIN FSM

   unique case (current_state)


       pkg ::  GC_IDLE : begin
              if(!mshr_commit_valid)begin
                 l2_req_ready = 1 ;
                 if(l2_req_valid)begin
                    cur.valid = 1 ;
                    cur.index = l2_req.addr[TM_INDEX_BITS + 5 :6] ;
                    cur.tag = l2_req.addr[63: TM_INDEX_BITS + 6] ;

                    tm_read_enable = 1 ;
                    tm_index = l2_req.addr[TM_INDEX_BITS + 5 :6] ;

                    // next state
                    next_state = pkg::  GC_TAG_WAIT ;
                 end
              end
        end
       pkg :: GC_TAG_WAIT : begin
        //   i will improve here there is extra state
        // i thaught I will add pipelining so I add this state
         // till now there is no any pipeling
        next_state =  pkg :: GC_COMPARE ;
       end

       pkg :: GC_COMPARE : begin

        cur.hit = tc_hit ;
        cur.hit_way = tc_hit_way ;

        cur.way_tag[0] = tm_tag_way0;
        cur.way_tag[1] = tm_tag_way1;
        cur.way_tag[2] = tm_tag_way2;
        cur.way_tag[3] = tm_tag_way3;

        cur.way_valid_bits = tm_tag_valid;

        sr_req_valid = 1 ;

        if(cur.hit) begin

            sr_hit = 1 ;
            sr_hit_way = cur.hit_way ;

            da_rd_en = 1 ;
            da_rd_set = cur.index ;
            da_rd_way = cur.hit_way ;


            /// next state
            next_state = pkg :: GC_DATA ;
        end else begin

            sr_hit = 0 ;
            // next state ;
            next_state = pkg :: GC_VICTIM_WAIT ;
        end
       end


       pkg :: GC_DATA : begin

        if(cur.req.op == pkg :: REQ_WRITE_BACK) begin
            // merge the L1 writeback bytes into the current line and
            // write it straight back (write-hit, no LLC traffic needed).

            for (int  b = 0 ; b < L1_LINE_BYTES ;  b++) begin
                if(cur.req.wmask) begin
                        cur.req.wdata[b*8 +: 8] = da_rd_data[base + b*8 +: 8];
                end
            end

            da_wr_en = 1 ;
            da_wr_set = cur.index ;
            da_wr_way = cur.hit_way ;
            da_wr_data = da_rd_data ;
            da_wr_valid  = 1 ;
            da_wr_dirty = 1 ;

            cur.line_data = da_rd_data ;

            //next state 
            next_state = pkg ::  GC_RESPOND ;
        end
       end

       pkg :: GC_RESPOND  : begin

        if(!mshr_resp_valid) begin

            l2_resp.op  = (cur.req.op == pkg :: REQ_WRITE_BACK ) ? pkg ::  RESP_WB_ACK  :  pkg ::  RESP_FILL;
            l2_resp.gtag = cur.req.gtag ;
            l2_resp.sub_sel = cur.req.sub_sel ;
            l2_resp.data = cur.line_data ;
            l2_resp.error = 0 ;

            l2_resp_valid = 1 ;

            if(l2_resp_ready) begin
                cur.valid = 0 ;
                next_state = pkg ::  GC_IDLE ;
            end
            /// else : L1 side is not ready --  we have to stay in respond side
        end

       end

       pkg :: GC_VICTIM_WAIT : begin
        next_state = pkg ::  GC_VICTIM ;
       end


       pkg :: GC_VICTIM : begin

        cur.victim_way = sr_victim_way ;
        cur.victim_valid = sr_victim_valid ;

        da_rd_en = 1 ;
        da_rd_set = cur.index ;
        da_rd_way = cur.victim_way ;
        next_state =  pkg :: GC_VICTIM_DATA ;

       end


       pkg :: GC_VICTIM_DATA : begin

        cur.need_wb = da_rd_valid && da_rd_dirty ;
        cur.victim_tag = cur.way_tag[cur.victim_way] ;
        cur.victim_data = da_rd_data;

        mshr_alloc_req = 1 ;

        next_state =  pkg :: GC_ALLOC_WAIT ;
       end


       pkg :: GC_ALLOC_WAIT : begin 
        mshr_alloc_req = 1 ;
        next_state =   pkg :: GC_ALLOC_CHECK ;
       end


       pkg :: GC_ALLOC_CHECK : begin

        if(mshr_alloc_ready || mshr_alloc_secondary_hit )begin 
            cur.valid = 0 ;
            next_state = pkg ::  GC_IDLE ;
        end else  begin
           // this is for back pressure

           mshr_alloc_req = 1 ;

           next_state = pkg ::  GC_ALLOC_WAIT ;
        end
       end

        default  : begin

            next_state = pkg :: GC_IDLE ;

        end


    endcase


   //
   // assigning the cur to MSHR entries
   assign mshr_alloc_index = cur.index ;
   assign mshr_alloc_tag = cur.tag;
   assign mshr_alloc_op = cur.req.op ;
   assign mshr_alloc_way  = cur.victim_way ;
   assign mshr_alloc_victim_dirty = cur.need_wb ;
   assign mshr_alloc_victim_data = cur.victim_data ;
   assign mshr_alloc_victim_tag = cur.victim_tag ;
   assign mshr_alloc_gtag = cur.req.gtag ;
   assign mshr_alloc_sub_sel = cur.req.sub_sel ;
   assign mshr_alloc_wdata = cur.req.wdata ;
   assign mshr_alloc_wmask = cur.req.wmask ;

   
    end
end

endmodule
