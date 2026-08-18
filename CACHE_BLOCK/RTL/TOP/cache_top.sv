// top module of the cache memory

`timescale 1ns/1ps

module cache_top #(
    parameter int ADDR_W        = 64,
    parameter int L1_LINE_BYTES = 32,
    parameter int L2_LINE_BYTES = 64,
    parameter int MSHR_ENTRIES  = 8,
    parameter int TAG_W         = 3,  // this are the MSHR tag_ form which MSHR entries does this data belong
    parameter int LLC_ADDR_W     = 64,
    parameter int LLC_LINE_BYTES = 64,
    parameter int L2_MSHR_ENTRIES = 8,
    parameter int LLC_TAG_W    = 3, // there is also MSHR at the side of LLC
    parameter int TM_TAG_BITS = 47,
    parameter int MSHR_MAX_SEC = 3 ,
    parameter int NUM_WAYS = 4
) (
    // clock and reset_n
    input logic clk ,
    input logic rst_n ,

    // cpu side L1 side
    input logic  cpu_req_valid ,
    input  pkg :: l2_if_req_t  cpu_req ,
    output logic cpu_req_ready ,

    output pkg :: l2_if_resp_t cpu_resp ,
    output logic cpu_resp_valid ,
    input logic cpu_resp_ready ,

    // memory syde  LLC side
   output logic mem_req_valid ,
   output pkg :: l2_llc_req_t  mem_req ,
   input logic mem_req_ready ,

   input logic mem_resp_valid ,
   input pkg :: l2_llc_resp_t mem_resp ,
   output logic mem_resp_ready
);

// internal wiring signals
// Internal wiring signals
// tag_memory <-> global_control
// (+ fan-out to tag_compare)
    parameter  int NUM_SETS   = 2048;

    parameter  int INDEX_BITS = 11;
    parameter  int WAY_BITS   = $clog2(NUM_WAYS) ;
    parameter int L1_LINE_BITS  = L1_LINE_BYTES * 8;
    parameter int L2_LINE_BITS  = L2_LINE_BYTES * 8;
    parameter int REQ_DEPTH     = MSHR_ENTRIES;
    parameter int RESP_DEPTH    = MSHR_ENTRIES ;
    parameter  int LLC_LINE_BITS  = LLC_LINE_BYTES * 8;   // 512
    parameter int GTAG_W        = TAG_W + 1;
    parameter int  TM_INDEX_BITS = $clog2(NUM_SETS);



logic                         w_tm_read_enable;
logic [TM_INDEX_BITS-1:0]     w_tm_index;

logic [TM_TAG_BITS-1:0]       w_tm_tag_way0;
logic [TM_TAG_BITS-1:0]       w_tm_tag_way1;
logic [TM_TAG_BITS-1:0]       w_tm_tag_way2;
logic [TM_TAG_BITS-1:0]       w_tm_tag_way3;

logic [NUM_WAYS-1:0]       w_tm_tag_valid;

logic                         w_tm_write_enable;
logic [1:0]                   w_tm_write_way;
logic [TM_TAG_BITS-1:0]       w_tm_tag_in;
logic                         w_tm_valid_in;

// tag_compare <-> global_control
logic [TM_TAG_BITS-1:0]       w_tc_req_tag;
logic                         w_tc_hit;
logic                         w_tc_miss;
logic [1:0]                   w_tc_hit_way;


// srrip <-> global_control

logic                         w_sr_req_valid;
logic [TM_INDEX_BITS-1:0]        w_sr_index;
logic                         w_sr_hit;
logic [1:0]                   w_sr_hit_way;
logic [1:0]                   w_sr_victim_way;
logic                         w_sr_victim_valid;

// data_array <-> global_control
logic                         w_da_rd_en;
logic [10:0]                  w_da_rd_set;
logic [1:0]                   w_da_rd_way;

logic [L2_LINE_BITS-1:0]         w_da_rd_data;
logic                         w_da_rd_valid;
logic                         w_da_rd_dirty;

logic                         w_da_wr_en;
logic [10:0]                  w_da_wr_set;
logic [1:0]                   w_da_wr_way;

logic [L2_LINE_BITS-1:0]         w_da_wr_data;
logic                         w_da_wr_valid;
logic                         w_da_wr_dirty;


// mshr_table <-> global_control : allocate port
logic                         w_alloc_req;
logic [TM_INDEX_BITS-1:0]     w_alloc_index;
logic [TM_TAG_BITS-1:0]       w_alloc_tag;
logic [1:0]                   w_alloc_way;

logic                         w_alloc_victim_dirty;
logic [TM_TAG_BITS-1:0]       w_alloc_victim_tag;
logic [L2_LINE_BITS-1:0]         w_alloc_victim_data;

logic [GTAG_W-1:0]            w_alloc_gtag;

 pkg :: req_op_t                      w_alloc_op;

logic                         w_alloc_sub_sel;
logic [L1_LINE_BITS-1:0]      w_alloc_wdata;
logic [L1_LINE_BYTES-1:0]     w_alloc_wmask;

logic                         w_alloc_ready;
logic                         w_alloc_secondary_hit;
logic                         w_alloc_conflict;


// mshr_table <-> global_control : commit port
logic                         w_commit_valid;
logic [TM_INDEX_BITS-1:0]     w_commit_index;
logic [1:0]                   w_commit_way;
logic [TM_TAG_BITS-1:0]       w_commit_tag;
logic [L2_LINE_BITS-1:0]         w_commit_data;
logic                         w_commit_dirty;


// mshr_table <-> global_control : response arbitration port
 logic                         w_mshr_resp_valid;
 pkg :: l2_if_resp_t          w_mshr_resp;
 logic                         w_mshr_resp_ready;

 logic  [TM_TAG_BITS-1:0] w_tc_way_0 ;
 logic  [TM_TAG_BITS-1:0] w_tc_way_1 ;
 logic  [TM_TAG_BITS-1:0] w_tc_way_2 ;
 logic  [TM_TAG_BITS-1:0] w_tc_way_3 ;
 logic [3:0] w_tc_valid  ;

 srrip_controller #(
       .NUM_SETS(NUM_SETS),
       .NUM_WAYS(NUM_WAYS),
       .INDEX_BITS(INDEX_BITS),
       .WAY_BITS(WAY_BITS)
) controller (
         .clk(clk),
         .rst_n(rst_n),        // active-low sync reset

         .req_valid(w_sr_req_valid),    // a lookup is happening this cycle
         .index(w_sr_index),        // set index
         .hit(w_sr_hit),          // 1 = hit, 0 = miss
         .hit_way(w_sr_hit_way),      // valid only when hit==1 (0 on miss, per spec)

         .victim_way(w_sr_victim_way),   // valid only when hit==0 (the way to evict/fill)
         .victim_valid(w_sr_victim_valid)
);

    parameter int TM_ADDR_BITS     = 64;

 MSHR_CONTROL_AND_TABLE #(
      .TM_NUM_WAYS(NUM_WAYS),
      .TM_TAG_BITS(TM_TAG_BITS),
      .TM_INDEX_BITS(TM_INDEX_BITS),
      .TM_OFFSET_BITS(6),
      .TM_ADDR_BITS(TM_ADDR_BITS),
      .GTAG_W(GTAG_W),
      .L1_LINE_BITS(L1_LINE_BITS),
      .LLC_LINE_BITS(LLC_LINE_BITS),
      .MSHR_ENTRIES(MSHR_ENTRIES)
) MSHR_CONTROL (

    // CLOCK AND RESET
    .clk(clk),
    .rst_n(rst_n),

    // ALLOCATE / SECONDARY MERGE PORT
    // Driven by Global Control
    .alloc_req(w_alloc_req),
    .alloc_index(w_alloc_index),
    .alloc_tag(w_alloc_tag),
    .alloc_way(w_alloc_way),
    .alloc_victim_dirty(w_alloc_victim_dirty),
    .alloc_victim_tag(w_alloc_victim_tag),
    .alloc_victim_data(w_alloc_victim_data),
    .alloc_gtag(w_alloc_gtag),
    .alloc_op(w_alloc_op),
    .alloc_sub_sel(w_alloc_sub_sel),
    .alloc_wdata(w_alloc_wdata),
    .alloc_wmask(w_alloc_wmask),

    // ALLOCATION OUTPUT
    .alloc_ready(w_alloc_ready),
    .alloc_secondary_hit(w_alloc_secondary_hit),
    .alloc_full_and_write_conflict(w_alloc_conflict),

    // LLC FACING PORT
    .llc_req_valid(mem_req_valid),
    .llc_req(mem_req),
    .llc_req_ready(mem_req_ready),
    .llc_resp_valid(mem_resp_valid),
    .llc_resp(mem_resp),
    .llc_resp_ready(mem_resp_ready),


    // FILL COMMIT PORT
    // Tell Global Control to write tag/data array
    .commit_valid(w_commit_valid),
    .commit_index(w_commit_index),
    .commit_way(w_commit_way),
    .commit_tag(w_commit_tag),
    .commit_data(w_commit_data),
    .commit_dirty(w_commit_dirty),


    // UPSTREAM RESPONSE
    .resp_valid(w_mshr_resp_valid),
    .resp(w_mshr_resp),
    .resp_ready(w_mshr_resp_ready) // bug
);

 global_control #(
    .ADDR_W(ADDR_W),
    .L1_LINE_BYTES(L1_LINE_BYTES),
    .L2_LINE_BYTES(L2_LINE_BYTES),
    .L1_LINE_BITS(L1_LINE_BITS),
    .L2_LINE_BITS(L2_LINE_BITS),
    .MSHR_ENTRIES(MSHR_ENTRIES),
    .TAG_W(TAG_W),
    .GTAG_W(GTAG_W),
    // REQUEST / RESPONSE QUEUES

    .REQ_DEPTH(REQ_DEPTH),
    .RESP_DEPTH(RESP_DEPTH),

    // LLC PARAMETERS
    .LLC_ADDR_W(LLC_ADDR_W),
    .LLC_LINE_BYTES(LLC_LINE_BYTES),
    .LLC_LINE_BITS(LLC_LINE_BITS),
    .L2_MSHR_ENTRIES(L2_MSHR_ENTRIES),
    .LLC_TAG_W(LLC_TAG_W),

    // TAG MEMORY PARAMETERS
    .TM_NUM_SETS(NUM_SETS),
    .TM_NUM_WAYS(NUM_WAYS),
    .TM_INDEX_BITS(TM_INDEX_BITS),
    .TM_TAG_BITS(TM_TAG_BITS),
    .TC_TAG_BITS(TM_TAG_BITS),
    .INDEX_BITS (INDEX_BITS),
    .LINE_BITS (L2_LINE_BITS),
    .MSHR_MAX_SEC(MSHR_MAX_SEC)

) global_control (
    // CLOCK AND RESET
    .clk(clk),
    .rst_n(rst_n),
    // UPSTREAM / L1 FACING PORT
    .l2_req_valid(cpu_req_valid),
    .l2_req(cpu_req),
    .l2_req_ready(cpu_req_ready),

    .l2_resp_valid(cpu_resp_valid),
    .l2_resp(cpu_resp),
    .l2_resp_ready(cpu_resp_ready), // for handshake
    // TAG MEMORY PORT
    .tm_read_enable(w_tm_read_enable),
    .tm_index(w_tm_index),
    .tm_tag_way0(w_tm_tag_way0),
    .tm_tag_way1(w_tm_tag_way1),
    .tm_tag_way2(w_tm_tag_way2),
    .tm_tag_way3(w_tm_tag_way3),
    .tm_tag_valid(w_tm_tag_valid),

    // TAG MEMORY WRITE
    .tm_write_enable(w_tm_write_enable),
    .tm_write_way(w_tm_write_way),
    .tm_tag_in(w_tm_tag_in),
    .tm_valid_in(w_tm_valid_in),

    // TAG COMPARE PORT
    .tc_req_tag(w_tc_req_tag),
    .tc_hit(w_tc_hit),
    .tc_miss(w_tc_miss),
    .tc_hit_way(w_tc_hit_way),
    .tc_way_0 (w_tc_way_0),
    .tc_way_1 (w_tc_way_1),
    .tc_way_2 (w_tc_way_2),
    .tc_way_3 (w_tc_way_3),
    .tag_valid(w_tc_valid),


    // SRRIP REPLACEMENT CONTROLLER
    .sr_req_valid(w_sr_req_valid),
    .sr_index(w_sr_index),
    .sr_hit(w_sr_hit),
    .sr_hit_way(w_sr_hit_way),
    .sr_victim_way(w_sr_victim_way),
    .sr_victim_valid(w_sr_victim_valid),

    // DATA ARRAY READ PORT
    .da_rd_en(w_da_rd_en),
    .da_rd_set(w_da_rd_set),
    .da_rd_way(w_da_rd_way),
    .da_rd_data(w_da_rd_data),
    .da_rd_valid(w_da_rd_valid),
    .da_rd_dirty(w_da_rd_dirty),

    // DATA ARRAY WRITE PORT
    .da_wr_en(w_da_wr_en),
    .da_wr_set(w_da_wr_set),
    .da_wr_way(w_da_wr_way),
    .da_wr_data(w_da_wr_data),
    .da_wr_valid(w_da_wr_valid),
    .da_wr_dirty(w_da_wr_dirty),

    // MSHR TABLE
    // ALLOCATION / SECONDARY MERGE PORT
      .mshr_alloc_req(w_alloc_req),
      .mshr_alloc_index(w_alloc_index),
      .mshr_alloc_tag(w_alloc_tag),
      .mshr_alloc_way(w_alloc_way),
      .mshr_alloc_victim_dirty(w_alloc_victim_dirty),
      .mshr_alloc_victim_tag(w_alloc_victim_tag),
      .mshr_alloc_victim_data(w_alloc_victim_data),
      .mshr_alloc_gtag(w_alloc_gtag),
      .mshr_alloc_op(w_alloc_op),
      .mshr_alloc_sub_sel(w_alloc_sub_sel),
      .mshr_alloc_wdata(w_alloc_wdata),
      .mshr_alloc_wmask(w_alloc_wmask),

    // MSHR ALLOCATION RESPONSE
    .mshr_alloc_ready(w_alloc_ready),
    .mshr_alloc_secondary_hit(w_alloc_secondary_hit),
    .mshr_alloc_full_and_write_conflict(w_alloc_conflict),

    // MSHR TABLE
    // FILL COMMIT PORT
    .mshr_commit_valid(w_commit_valid),
    .mshr_commit_index(w_commit_index),
    .mshr_commit_way(w_commit_way),
    .mshr_commit_tag(w_commit_tag),
    .mshr_commit_data(w_commit_data),
     .mshr_commit_dirty(w_commit_dirty),

    // MSHR RESPONSE PORT
    // MSHR -> Global Control -> L1
    // Global control arbitrates the response.
     .mshr_resp_valid(w_mshr_resp_valid),
     .mshr_resp(w_mshr_resp),
     .mshr_resp_ready(w_mshr_resp_ready) //bug
);


 data_array #(
    .CACHE_SETS(NUM_SETS),
    .CACHE_WAYS(NUM_WAYS),
    .LINE_BITS(L2_LINE_BITS)
) data_array (
    // Clock / Reset
    .clk(clk),
    .rst_n(rst_n),

    // Read Port
     .rd_en(w_da_rd_en),
     .rd_set(w_da_rd_set),
     .rd_way(w_da_rd_way),

     .rd_data(w_da_rd_data),
     .rd_valid(w_da_rd_valid),
     .rd_dirty(w_da_rd_dirty),

    // Write Port
     .wr_en(w_da_wr_en),
     .wr_set(w_da_wr_set),
     .wr_way(w_da_wr_way),

     .wr_data(w_da_wr_data),
     .wr_valid(w_da_wr_valid),
     .wr_dirty(w_da_wr_dirty)
);

 tag_compare  #(
  .TC_TAG_BITS(TM_TAG_BITS)
)tag_compare(
     .tag_valid(w_tc_valid),  //  here is the problem 
     .req_tag(w_tc_req_tag),
     .tag_way0(w_tc_way_0),
     .tag_way1(w_tc_way_1),
     .tag_way2(w_tc_way_2),
     .tag_way3(w_tc_way_3),
     .hit(w_tc_hit),
     .hit_way(w_tc_hit_way) ,
     .miss(w_tc_miss)
);

 tag_memory #(
    .TM_NUM_SETS(NUM_SETS),
    .TM_NUM_WAYS (NUM_WAYS),
    .TM_INDEX_BITS(INDEX_BITS),
    .TM_OFFSET_BITS(6) ,
    .TM_ADDR_BITS (TM_ADDR_BITS) ,
    .TM_TAG_BITS(TM_TAG_BITS)
)tag_memory(
      .clk(clk),
      .rst_n(rst_n),


    // input
    .tag_read_enable(w_tm_read_enable),
    .tag_index(w_tm_index), //  shared index for read and write


    .tag_way0(w_tm_tag_way0),
    .tag_way1(w_tm_tag_way1),
    .tag_way2(w_tm_tag_way2),
    .tag_way3(w_tm_tag_way3),


    .tag_valid(w_tm_tag_valid) ,
    .write_enable(w_tm_write_enable),
    .write_way(w_tm_write_way),  // we need to debug here
    .write_tag(w_tm_tag_in)
);


endmodule
