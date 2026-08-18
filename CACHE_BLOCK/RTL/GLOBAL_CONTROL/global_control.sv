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
    output  logic  [TC_TAG_BITS-1:0]   tc_way_0 ,
    output  logic  [TC_TAG_BITS-1:0]   tc_way_1 ,
    output  logic  [TC_TAG_BITS-1:0]   tc_way_2 ,
    output  logic  [TC_TAG_BITS-1:0]   tc_way_3 ,
    output  logic [3:0]                 tag_valid,

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

pkg :: gc_request_t cur_current , cur_next ;
always_ff @(posedge clk ) begin

    if(!rst_n) begin
        current_state <= pkg::  GC_IDLE;
        cur_current <= '{default : 0 } ;
    end else
        current_state <= next_state;
        cur_current <= cur_next  ;
end

int base ;
assign  base = cur_current.req.sub_sel ? L1_LINE_BITS : 0;
always_comb begin
///$monitor("l2_request_operation  = " , l2_req.op);

    // difault values  to avoid latch
    cur_next = cur_current ;
    next_state = pkg :: GC_IDLE;
    tm_read_enable = 0 ;
    tm_index = 0 ;
    tm_write_enable  = 0 ;
    tm_write_way = 0 ;
    tm_tag_in = 0 ;
    tm_valid_in = 0 ;

    mshr_alloc_wdata  = 0 ;
    mshr_alloc_wmask = 0 ;

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
    mshr_alloc_index =  0 ;
    mshr_alloc_gtag = 0 ;
    mshr_alloc_op = pkg :: REQ_READ ;
    mshr_alloc_sub_sel = 0 ;
    mshr_alloc_tag = 0 ;
    mshr_alloc_victim_data = 0 ;
    mshr_alloc_way = 0;
    mshr_alloc_victim_dirty = 0 ;
    l2_resp_valid = 0 ;
    l2_resp = 0 ;
    l2_req_ready = 0 ;
    mshr_alloc_victim_tag = 0 ;
    tc_req_tag = 0 ;
    tc_way_0 = 0 ;
    tc_way_1 = 0 ;
    tc_way_2 = 0 ;
    tc_way_3 = 0 ;
    tag_valid = 0;
    sr_index = 0 ;

    if(!rst_n)begin
     cur_next.valid = 1'b0 ;
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
        da_wr_valid = 1;
      end

      //  responce arbitration ---
      // here is the problem combinational loop
      mshr_resp_ready = l2_resp_ready ;
      if(mshr_resp_valid)begin
        l2_resp_valid = 1 ;
        l2_resp = mshr_resp ;
      end

    //   MAIN FSM
   unique case (current_state)
       pkg ::  GC_IDLE : begin
              if(!mshr_commit_valid)begin
                 l2_req_ready = 1 ;
                 if(l2_req_valid)begin
                    cur_next.req = l2_req;
                    cur_next.valid = 1 ;
                    cur_next.index = l2_req.addr[TM_INDEX_BITS + 5 :6] ;
                    cur_next.tag = l2_req.addr[63: TM_INDEX_BITS + 6] ;
                    tm_read_enable = 1 ;
                    tm_index = l2_req.addr[TM_INDEX_BITS + 5 :6] ;
                    cur_next.way_tag[0] = tm_tag_way0;
                    cur_next.way_tag[1] = tm_tag_way1;
                    cur_next.way_tag[2] = tm_tag_way2;
                    cur_next.way_tag[3] = tm_tag_way3;
                    cur_next.way_valid_bits = tm_tag_valid;
                    // next state
                    next_state = pkg::  GC_COMPARE ;
                 end
              end
        end

       pkg :: GC_COMPARE : begin

          tc_way_0 = cur_current.way_tag[0];
          tc_way_1 = cur_current.way_tag[1];
          tc_way_2 = cur_current.way_tag[2];
          tc_way_3 = cur_current.way_tag[3];
          tc_req_tag = cur_current.tag;
          tag_valid = cur_current.way_valid_bits ;


        cur_next.hit = tc_hit ;
        cur_next.hit_way = tc_hit_way ;

        sr_req_valid = 1 ;

        if(tc_hit) begin

            sr_hit = 1 ;
            sr_hit_way = tc_hit_way ;

            da_rd_en = 1 ;
            da_rd_set = cur_current.index ;
            da_rd_way = cur_current.hit_way ;


            /// next state
            next_state = pkg :: GC_DATA ;
        end else begin

            sr_hit = 0 ;
            // next state ;
            next_state = pkg :: GC_VICTIM ;
        end
       end


       pkg :: GC_DATA : begin

        if(cur_current.req.op == pkg :: REQ_WRITE_BACK) begin
            // merge the L1 writeback bytes into the current line and
            // write it straight back (write-hit, no LLC traffic needed).
            for (int  b = 0 ; b < L1_LINE_BYTES ;  b++) begin
                if(cur_current.req.wmask[b]) begin
                        cur_next.req.wdata[b*8 +: 8] = da_rd_data[base + b*8 +: 8];
                end
            end

            da_wr_en = 1 ;
            da_wr_set = cur_current.index ;
            da_wr_way = cur_current.hit_way ;
            da_wr_data = da_rd_data ;
            da_wr_valid  = 1 ;
            da_wr_dirty = 1 ;
            //next state
            next_state = pkg ::  GC_RESPOND ;
        end   else begin
        // this is read request
        da_rd_en = 1 ;
        da_rd_set  = cur_current.index;
        da_rd_way = cur_current.hit_way ;
        cur_next.line_data = da_rd_data ;
        $monitor("data from memory is " ,da_rd_data ) ;
        next_state = pkg :: GC_RESPOND ;

        end
       end

       pkg :: GC_RESPOND  : begin

        if(!mshr_resp_valid) begin

          ///  $monitor("current operation is " , cur_current.req.op ) ;
            if(cur_current.req.op == pkg :: REQ_WRITE_BACK ) begin
            l2_resp.op  =  pkg ::  RESP_WB_ACK ;
            l2_resp.gtag = cur_current.req.gtag ;
            l2_resp.sub_sel = cur_current.req.sub_sel ;
            l2_resp.data =  '0 ; //problem solved
            l2_resp.error = 0 ;
            end else begin
            l2_resp.op  =  pkg ::  RESP_FILL ;
            l2_resp.gtag = cur_current.req.gtag ;
            l2_resp.sub_sel = cur_current.req.sub_sel ;
            if(cur_current.req.sub_sel)begin
            l2_resp.data =   cur_current.line_data[511 : 256 ] ; //problem solved
            end else  l2_resp.data =   cur_current.line_data[255 : 0 ] ; //problem solved
            l2_resp.error = 0 ;
            end
            l2_resp_valid = 1 ;

            if(l2_resp_ready) begin
                cur_next.valid = 0 ;
                next_state = pkg ::  GC_IDLE ;
            end
            /// else : L1 side is not ready --  we have to stay in respond side
        end

       end



       pkg :: GC_VICTIM : begin

        cur_next.victim_way = sr_victim_way ;
        cur_next.victim_valid = sr_victim_valid ;

        da_rd_en = 1 ;
        da_rd_set = cur_current.index ;
        da_rd_way = cur_current.victim_way ;
        next_state =  pkg :: GC_VICTIM_DATA ;

       end


       pkg :: GC_VICTIM_DATA : begin

        cur_next.need_wb = da_rd_valid && da_rd_dirty ;
        cur_next.victim_tag = cur_current.way_tag[cur_current.victim_way] ;
        cur_next.victim_data = da_rd_data;

        next_state =  pkg :: GC_ALLOC_WAIT ;
       end


       pkg :: GC_ALLOC_WAIT : begin
        mshr_alloc_req = 1 ;
        next_state =   pkg :: GC_ALLOC_CHECK ;
       end

       pkg :: GC_ALLOC_CHECK : begin

        if(mshr_alloc_ready || mshr_alloc_secondary_hit )begin 
            cur_next.valid = 0 ;
            next_state = pkg ::  GC_IDLE ;
        end else  begin
           // this is for back pressure
           next_state = pkg ::  GC_ALLOC_WAIT ;
        end
       end

        default  : begin

            next_state = pkg :: GC_IDLE ;

        end


    endcase

   // assigning the cur to MSHR entries
   assign mshr_alloc_index = cur_current.index ;
   assign mshr_alloc_tag = cur_current.tag;
   assign mshr_alloc_op = cur_current.req.op ;
   assign mshr_alloc_way  = cur_current.victim_way ;
   assign mshr_alloc_victim_dirty = cur_current.need_wb ;
   assign mshr_alloc_victim_data = cur_current.victim_data ;
   assign mshr_alloc_victim_tag = cur_current.victim_tag ;
   assign mshr_alloc_gtag = cur_current.req.gtag ;
   assign mshr_alloc_sub_sel = cur_current.req.sub_sel ;
   assign mshr_alloc_wdata = cur_current.req.wdata ;  // write operation can be miss
   assign mshr_alloc_wmask = cur_current.req.wmask ;  // this is for that
    end
end
endmodule
