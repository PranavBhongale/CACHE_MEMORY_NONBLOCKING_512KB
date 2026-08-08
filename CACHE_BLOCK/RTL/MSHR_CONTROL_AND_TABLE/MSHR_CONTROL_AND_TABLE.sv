`timescale 1ns/1ps

module MSHR_CONTROL_AND_TABLE #(
    parameter int TM_NUM_SETS = 2048,
    parameter int TM_NUM_WAYS= 4,
    parameter int TM_TAG_BITS = 47 ,
    parameter int TM_INDEX_BITS = 11 ,
    parameter int TM_OFFSET_BITS = 6 ,
    parameter int TM_ADDR_BITS = 64 ,
    parameter int GTAG_W = TM_TAG_BITS ,
    parameter int L1_LINE_BITS = 256,
    parameter int LLC_LINE_BITS = 512

) (
// CLOCK AND RESET

input logic clk ,
input logic rst_n ,

//allocate secondary merg - port (driven by global control )
input logic alloc_req ,
input logic [TM_INDEX_BITS -1 : 0 ]   alloc_index ,
input logic [TM_TAG_BITS -1 : 0 ] alloc_tag ,
input logic [1 : 0 ]  alloc_way ,
input logic alloc_victim_dirty ,
input logic [TM_TAG_BITS -1 : 0 ] alloc_victim_tag,
input logic [511 : 0 ] alloc_victim_data,
input logic [GTAG_W -1 : 0 ] alloc_gtag,
input pkg :: req_op_t alloc_op,
input logic alloc_sub_sel,
input logic [L1_LINE_BITS -1 : 0 ] alloc_wdata,
input logic [L1_LINE_BITS/8 -1 : 0 ] alloc_wmask,



//output
output logic alloc_ready ,  // we can allocate free entry is exist
output logic alloc_secondary_hit , // even though the entry is not available but if the request are
                                    // same we can allocate
output logic alloc_full_and_write_conflict , // 1 = alloc_req is a WRITE_BACK then collide with read the same entry
                                             // istead of sending request we can give data from MSHR entry if data is there



//  llc_facing_port
output llc_req_valid ,
output  pkg :: l2_llc_req_t llc_req,
input logic llc_req_ready,

input logic llc_resp_valid,
input pkg :: l2_llc_resp_t llc_resp ,
output logic llc_resp_ready ,

  // fill commit port ( tell globle control to write tad_memory and data array )

  output logic commit_valid,
  output logic [TM_INDEX_BITS  -1 : 0] commit_index ,
  output logic [1 : 0 ] commit_way,
  output logic [TM_TAG_BITS -1 : 0 ] commit_tag ,
  output logic [LLC_LINE_BITS -1 : 0 ] commit_data ,
  output logic commit_dirty ,

// upstream_responce 

output logic resp_valid ,
output  pkg :: l2_if_resp_t resp ,
input logic resp_ready
);

pkg :: mshr_entry_t entry ;


// finit state machine of MSHR TABLE



endmodule


