package  pkg ;

    parameter int ADDR_W        = 64;
    parameter int L1_LINE_BYTES = 32;
    parameter int L2_LINE_BYTES = 64;
    parameter int L1_LINE_BITS  = L1_LINE_BYTES * 8;
    parameter int L2_LINE_BITS  = L2_LINE_BYTES * 8;
    parameter int MSHR_ENTRIES  = 8;
    parameter int TAG_W         = 3;
    parameter int GTAG_W        = TAG_W + 1;

    parameter int REQ_DEPTH     = MSHR_ENTRIES;
    parameter int RESP_DEPTH    = MSHR_ENTRIES ;

    parameter    int LLC_ADDR_W     = 64;
    parameter  int LLC_LINE_BYTES = 64;
    parameter  int LLC_LINE_BITS  = LLC_LINE_BYTES * 8;   // 512
    parameter   int L2_MSHR_ENTRIES = 8;
    parameter   int LLC_TAG_W    = 3;


    typedef enum logic {
        LLC_REQ_READ,
         LLC_REQ_WRITE_BACK
     }l2_llc_req_op_t ;


     typedef enum logic  {
         LLC_RESP_FILL,
         LLC_RESP_WB_ACK
      } l2_llc_resp_op_t;



typedef struct packed {
    logic              valid ;
    l2_llc_req_op_t     op;
    logic [LLC_ADDR_W-1:0 ] addr ;
    logic  [LLC_TAG_W-1:0 ] tag ;
    logic [LLC_LINE_BITS-1:0 ] wdata;
    logic [LLC_LINE_BYTES-1:0 ] wmask ;

} l2_llc_req_t;
    typedef struct packed {
    logic valid ;
    l2_llc_resp_op_t op ;
    logic [LLC_TAG_W-1 : 0] tag ;
    logic [LLC_LINE_BITS-1 :0 ] data;
    logic error ; // high then error if it is low there is no any error
    } l2_llc_resp_t;


typedef  enum logic  { REQ_READ, REQ_WRITE_BACK } req_op_t ;
typedef enum logic   { RESP_FILL, RESP_WB_ACK }resp_op_t ;

typedef struct packed {
   logic valid ;
   req_op_t op ;
   logic [ADDR_W-1 :0 ] addr ;
   logic [TAG_W -1 :0 ] tag ;
   logic sub_sel;
   logic [L1_LINE_BITS-1 : 0 ] wdata;
   logic [L1_LINE_BYTES-1 : 0 ] wmask ;
} l2_req_t;


typedef struct packed {
   logic valid ;
   resp_op_t                op;
   logic [TAG_W-1 : 0 ] tag ;
   logic sub_sel;
   logic [L1_LINE_BITS-1 : 0 ] data ;
   logic error ;
} l2_resp_t ;

typedef struct packed {
    req_op_t op ;
    logic [ADDR_W -1 :0 ] addr ;
    logic [GTAG_W -1 :0 ] gtag ;
    logic sub_sel ;
    logic [L1_LINE_BITS -1 : 0 ] wdata;
    logic [L1_LINE_BYTES -1 : 0 ] wmask ;

} l2_if_req_t;

typedef struct packed {
    resp_op_t op ;
    logic [GTAG_W -1 :0 ] gtag ;
    logic sub_sel ;
    logic [L1_LINE_BITS-1 : 0 ] data ;
    logic error ;
} l2_if_resp_t ;


typedef enum logic [2:0] {
    MSHR_IDLE,       // entry free
    MSHR_WB_SEND,    // need to evict a dirty victim first; waiting for LLC port
    MSHR_WB_WAIT,    // writeback request accepted; waiting for WB_ACK from LLC
    MSHR_FILL_SEND,  // ready to request the new line; waiting for LLC port
    MSHR_FILL_WAIT,  // fill request accepted; waiting for RESP_FILL from LLC
    MSHR_COMMIT,     // fill data arrived this cycle; ask global_control to write the arrays
    MSHR_RESP     // draining response (primary  , then secondary )  back to l1
} mshr_state_t ;

typedef struct packed {

logic valid ;
mshr_entry_t state ;

// identity of the line being installed

logic [TM_INDEX_BITS-1 : 0 ] index ;
logic [TM_TAG_BITS -1 : 0 ] line_tag ;
logic [1 : 0 ] way ;


// eviction information write before fill
logic need_wb ;
logic [TM_TAG_BITS -1 : 0 ] wb_tag ;
logic [LLC_LINE_BITS -1 : 0 ] wb_data;

// primery requester the one  that cause the allocation

logic [ GTAG -1 : 0 ] gtag ;
req_op_t op ;
logic sub_sel;
logic [L1_LINE_BITS -1 : 0 ] wdata ;
logic [L1_LINE_BYTES -1 : 0 ] wmask ;

// secondary request same request from different sourse
logic [31 : 0 ] num_sec;
logic [GTAG_W -1 : 0 ] sec_gtag[MSHR_MAX_SEC];
logic sec_sub_sel[MSHR_MAX_SEC];


    //  fill result, latched when RESP_FILL arrives 
  logic [LLC_LINE_BITS -1  : 0 ]  fill_data;
  logic [2 : 0 ]resp_next ;

} mshr_entry_t;


endpackage : pkg


