`timescale 1ns/1ps

module MSHR_CONTROL_AND_TABLE #(
    parameter int TM_NUM_WAYS      = 4, // @suppress "Parameter 'TM_NUM_WAYS' is never used locally"
    parameter int TM_TAG_BITS      = 47,
    parameter int TM_INDEX_BITS    = 11,
    parameter int TM_OFFSET_BITS   = 6, // @suppress "Parameter 'TM_OFFSET_BITS' is never used locally"
    parameter int TM_ADDR_BITS     = 64, // @suppress "Parameter 'TM_ADDR_BITS' is never used locally"
    parameter int GTAG_W           = TM_TAG_BITS,
    parameter int L1_LINE_BITS     = 256,
    parameter int LLC_LINE_BITS    = 512,
    parameter int MSHR_ENTRIES     = 8
) (
    // CLOCK AND RESET
    input logic clk,
    input logic rst_n,

    // ALLOCATE / SECONDARY MERGE PORT
    // Driven by Global Control
    input logic alloc_req,
    input logic [TM_INDEX_BITS-1:0] alloc_index,
    input logic [TM_TAG_BITS-1:0] alloc_tag,
    input logic [1:0] alloc_way,
    input logic alloc_victim_dirty,
    input logic [TM_TAG_BITS-1:0] alloc_victim_tag,
    input logic [511:0] alloc_victim_data,
    input logic [GTAG_W-1:0] alloc_gtag,
    input pkg::req_op_t alloc_op,
    input logic alloc_sub_sel,
    input logic [L1_LINE_BITS-1:0] alloc_wdata,
    input logic [L1_LINE_BITS/8-1:0] alloc_wmask,

    // ALLOCATION OUTPUT
    output logic alloc_ready,
    output logic alloc_secondary_hit,
    output logic alloc_full_and_write_conflict,

    // LLC FACING PORT
    output logic llc_req_valid,
    output pkg::l2_llc_req_t llc_req,
    input logic llc_req_ready,
    input logic llc_resp_valid,
    input pkg::l2_llc_resp_t llc_resp,
    output logic llc_resp_ready,


    // FILL COMMIT PORT
    // Tell Global Control to write tag/data array
    output logic commit_valid,
    output logic [TM_INDEX_BITS-1:0] commit_index,
    output logic [1:0] commit_way,
    output logic [TM_TAG_BITS-1:0] commit_tag,
    output logic [LLC_LINE_BITS-1:0] commit_data,
    output logic commit_dirty,


    // UPSTREAM RESPONSE
    output logic resp_valid,
    output pkg::l2_if_resp_t resp,
    input logic resp_ready

);
    // MSHR TABLE
    pkg::mshr_entry_t e_current[MSHR_ENTRIES] ,  e_next[MSHR_ENTRIES] ;

    // NEXT VALUES FOR REGISTERED MSHR FIELDS
    // current_state and next_state are both inside e[i].
    // These are only required for fields such as valid and
    // resp_next which are actual registered state.

    // RESPONSE ARBITRATION
    // MSHR 0 has highest priority.
    logic found;

    // for LLC_request;
    logic llc_wb_started ;

      pkg :: mshr_state_t current_state[MSHR_ENTRIES] , next_state[MSHR_ENTRIES] ;

    // MSHR STATE / REGISTER UPDATE
    always_ff @(posedge clk) begin

        if (!rst_n) begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                current_state[i] <= pkg::MSHR_IDLE;
                e_current[i].valid <= '0 ;
                e_current[i].index <= '0 ;
                e_current[i].line_tag <= '0 ;
                e_current[i].way <= '0 ;
                e_current[i].need_wb <= '0 ;
                e_current[i].wb_tag <= '0 ;
                e_current[i].wb_data <= '0 ;
                e_current[i].gtag <= '0 ;
                e_current[i].sub_sel <= '0 ;
                e_current[i].wdata <= '0 ;
                e_current[i].wmask <='0 ;
                e_current[i].num_sec <= '0 ;
                e_current[i].sec_gtag[0] <= '0 ;
                e_current[i].sec_gtag[1] <= '0 ;
                e_current[i].sec_gtag[2] <= '0 ;
                e_current[i].sec_sub_sel <= '0 ;
                e_current[i].fill_data <= '0 ;
                e_current[i].resp_next <='0 ;
                e_current[i].op <=  pkg :: REQ_READ ;
            end
        end
        else begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                current_state[i] <= next_state[i];
                e_current[i] <= e_next[i] ;
            end
        end
    end

    // break for commit the data
    logic one_commit;
    logic secondary_hit ;
    logic write_conflict ;
    logic have_free ;
    int free_idx  ;
    int match_idx  ;
    logic dirty;
    int base ;
    // COMBINATIONAL CONTROL
    always_comb begin : FSM
        // DEFAULT OUTPUT VALUES
        e_next = e_current ;
        next_state = current_state ;
        base = 0 ;
        dirty = 0;
        found = 0 ;
        llc_wb_started = 0;
         one_commit = 0 ;
         secondary_hit = 0   ;
         write_conflict = 0  ;
         have_free = 0  ;
         free_idx  = -1  ;
         match_idx  = -1  ;
         alloc_ready = 1'b0;
         alloc_full_and_write_conflict = 1'b0;
         alloc_secondary_hit = 1'b0;
         // LLC request
         llc_req_valid = 1'b0;
         llc_req = '0;
         // LLC response
         llc_resp_ready = 1'b0;
         // Commit
         commit_valid = 1'b0;
         commit_index = '0;
         commit_way = '0;
         commit_data = '0;
         commit_dirty = 1'b0;
         commit_tag = '0;
         // Upstream response
         resp_valid = 1'b0;
         resp = '0;
         // DEFAULT NEXT VALUES
        // RESPONSE ARBITRATION
        found = 1'b0;
        if (rst_n) begin
            for (int i = 0; i < MSHR_ENTRIES; i++) begin
                // FIND FIRST MSHR WITH A RESPONSE READY THEN STOP THE LOOP so one response per cycle
                // MSHR0 has highest priority.
                if (!found && e_current[i].valid && (current_state[i] == pkg::MSHR_RESP)) begin
                    // PRIMARY RESPONSE
                    if (e_current[i].resp_next == 3'b111) begin   //problem  solved
                        // Response type
                        resp.op =  (e_current[i].op == pkg::REQ_WRITE_BACK) ? pkg::RESP_WB_ACK  : pkg::RESP_FILL;
                        // Primary request information
                        resp.gtag = e_current[i].gtag;
                        resp.sub_sel = e_current[i].sub_sel;
                        if(e_current[i].sub_sel) begin
                        resp.data = e_current[i].fill_data[511:256];// problem  of bit width solved
                        end else begin  resp.data = e_current[i].fill_data[255:0]; end //problem solved

                        resp.error = '0;
                        // Response is valid
                        resp_valid = 1'b1;
                        // This MSHR has won arbitration.
                        // Remaining MSHRs are ignored for this cycle.
                        found = 1'b1;
                        // RESPONSE HANDSHAKE
                        if (resp_ready) begin
                            // Primary response has been accepted.
                            // Next response will be secondary[0].
                            e_next[i].resp_next = 0;
                            // No secondary requests
                            // Entire MSHR transaction is complete.
                            if (e_current[i].num_sec == 0) begin
                                e_next[i].valid = 1'b0;
                                next_state[i] = pkg::MSHR_IDLE;
                            end
                        end
                    end
                    // SECONDARY RESPONSE
                    else if (e_current[i].resp_next < e_current[i].num_sec) begin
                        // Secondary response
                        resp.op = pkg::RESP_FILL;
                        resp.gtag = e_current[i].sec_gtag[2'(e_current[i].resp_next)];
                        resp.sub_sel =  e_current[i].sec_sub_sel[2'(e_current[i].resp_next)];
                        // All secondary requests receive the same
                        // filled cache line.
                        if(e_current[i].sec_sub_sel[2'(e_current[i].resp_next)])begin 
                        resp.data = e_current[i].fill_data[511:256];
                        end else resp.data = e_current[i].fill_data[255:0];
                        resp.error = '0;
                        // Response is valid
                        resp_valid = 1'b1;
                        // This MSHR wins arbitration.
                        found = 1'b1;
                        // RESPONSE HANDSHAKE
                        if (resp_ready) begin
                            // Move to next secondary request.
                            e_next[i].resp_next =   e_current[i].resp_next + 1;
                            if ((e_current[i].resp_next + 3'b001) >= e_current[i].num_sec) begin
                                e_next[i].valid = 1'b0;
                                next_state[i] = pkg::MSHR_IDLE;
                            end
                        end
                    end
                end
            end


            llc_wb_started = 0;
            // 2)  Issue one LLC request
            for(int i = 0 ; i < MSHR_ENTRIES ; i++  )begin
              if(!llc_req_valid) begin
                 if(e_current[i].valid && current_state[i] == pkg :: MSHR_WB_SEND) begin
                    llc_req_valid = 1;
                    llc_req.op = pkg :: LLC_REQ_WRITE_BACK ;
                    llc_req.addr = {e_current[i].wb_tag , e_current[i].index , 6'b000000 } ; // we make here address
                    llc_req.tag = 3'(i) ; // MSHR index is LLC tag mshr will handel where to store after
                                        // important to give Acknowledge signal
                    llc_req.wdata = e_current[i].wb_data ;  ////  here is the problem of width 
                    llc_req.wmask = 64'hffffffffffffffff ;   // here also
                    if(llc_req_ready)begin
                        next_state[i] = pkg :: MSHR_WB_WAIT ;
                        llc_wb_started = 1;
                    end
                end else
                if(e_current[i].valid && current_state[i] == pkg :: MSHR_FILL_SEND ) begin
                  llc_req_valid = 1;
                  llc_req.op = pkg :: LLC_REQ_READ ;
                  llc_req.addr = {e_current[i].wb_tag , e_current[i].index , 6'b000000 } ;
                  llc_req.tag = 3'(i); //  this is the tag that we have to give
                  llc_req.wdata = 0 ;
                  llc_req.wmask = 0 ;
                  if(llc_req_ready)begin
                      next_state[i] = pkg :: MSHR_FILL_WAIT ;
                      llc_wb_started = 1;
                  end
                end else if (e_current[i].valid && current_state[i] == pkg :: MSHR_FILL_WAIT || 
                    current_state[i] == pkg :: MSHR_WB_WAIT ) begin 
                        llc_resp_ready = 1 ;
                    end
            end
        end

     if(llc_resp_valid) begin
        if(1) begin
             if (e_current[llc_resp.tag].valid && current_state[llc_resp.tag] == pkg :: MSHR_WB_WAIT && llc_resp.op ==  pkg :: LLC_RESP_WB_ACK) begin
                 next_state[llc_resp.tag] = pkg :: MSHR_FILL_SEND ;
             end else  if (e_current[llc_resp.tag].valid && current_state[llc_resp.tag] == pkg :: MSHR_FILL_WAIT && llc_resp.op ==  pkg :: LLC_RESP_FILL ) begin 
                e_next[llc_resp.tag].fill_data = llc_resp.data ;
                next_state[llc_resp.tag] = pkg ::  MSHR_COMMIT ;
             end
        end
     end

      // commit one entry (apply any pending write merge here )
      //   globle control will handel the commit
     one_commit = 0;
    for(int i = 0 ; i < MSHR_ENTRIES ; i++ )begin
        if(!one_commit) begin
        if(e_current[i].valid && current_state[i] ==  pkg :: MSHR_COMMIT) begin
            if(e_current[i].op ==  pkg:: REQ_WRITE_BACK)begin
                 base = e_current[i].sub_sel ? L1_LINE_BITS : 0 ;
                for(int b = 0 ; b < L1_LINE_BITS/8 ; b++ ) begin
                    if(e_current[i].wmask[b])begin
                     e_next[i].fill_data[base + b*8 +: 8] =  e_current[i].wdata[b*8 +: 8];
                    end
                end
                dirty = 1 ;
            end

            commit_valid = 1 ;
            commit_index = e_current[i].index ;
            commit_way = e_current[i].way ;
            commit_tag = e_current[i].line_tag;
            commit_data = e_current[i].fill_data ;
            commit_dirty = dirty ;
            next_state[i] = pkg:: MSHR_RESP ;// and here
            e_next[i].resp_next = -1 ;  // might we need to debug here
            one_commit = 1 ;
        end
    end
    end



  //  5) Accept a new allocation / or secondary - merge request

  for (int  i  = 0 ;  i < pkg :: MSHR_ENTRIES ;  i++ ) begin
    if(!e_current[i].valid) begin
        have_free = 1 ;
        alloc_ready = 1 ;
        if(free_idx < 0 )
            free_idx = i;
    end
  end

// to allocate the new request
  if(alloc_req)begin
    for(int i = 0 ; i < MSHR_ENTRIES  ; i++) begin
        if(e_current[i].valid && e_current[i].index == alloc_index  &&  e_current[i].line_tag == alloc_tag) begin
           match_idx = i ;
           break ;
        end
    end

    if(match_idx >= 0) begin
        if(alloc_op ==  pkg :: REQ_READ) begin
             if((e_current[match_idx].num_sec < 3'(pkg ::  MSHR_MAX_SEC) )&& (current_state[match_idx] != (pkg:: MSHR_RESP)))begin
                 e_next[match_idx].sec_gtag[(match_idx)] = alloc_gtag;
                 e_next[match_idx].sec_sub_sel[2'(e_current[match_idx].num_sec)] = alloc_sub_sel;
                 e_next[match_idx].num_sec = e_current[match_idx].num_sec + 1  ;
                 secondary_hit = 1 ;
             end
        end  else begin
            write_conflict = 1 ;
        end

    end else if (have_free)begin
         e_next[free_idx].valid = 1 ;
         e_next[free_idx].index = alloc_index ;
         e_next[free_idx].line_tag = alloc_tag ;
         e_next[free_idx].way = alloc_way ;
         e_next[free_idx].need_wb = alloc_victim_dirty;
         e_next[free_idx].wb_tag = alloc_victim_tag;
         e_next[free_idx].wb_data = alloc_victim_data;
         e_next[free_idx].gtag = alloc_gtag ;
         e_next[free_idx].op = alloc_op ;
         e_next[free_idx].sub_sel = alloc_sub_sel ;
         e_next[free_idx].wdata = alloc_wdata ;
         e_next[free_idx].wmask = alloc_wmask ;
         next_state[free_idx] = alloc_victim_dirty ? pkg:: MSHR_WB_SEND :  pkg:: MSHR_FILL_SEND ;
    end
    end
    end
  end
endmodule
