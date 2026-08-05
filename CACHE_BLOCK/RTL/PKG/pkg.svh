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

endpackage : pkg


