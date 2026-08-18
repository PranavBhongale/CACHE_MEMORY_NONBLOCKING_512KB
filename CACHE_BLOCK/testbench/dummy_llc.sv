module dummy_llc #(
    parameter int MEM_LINES       = 2048,
    parameter int LINE_BITS       = 512,
    parameter int ADDR_BITS       = 64,
    parameter int TAG_BITS        = 3,
    parameter int RESP_LATENCY    = 10,
    parameter int MAX_OUTSTANDING = 4  // how many transactions can be in flight at once —
                                         // match this to your DUT's L2_MSHR_ENTRIES / MSHR_ENTRIES
)(
    input  logic clk,
    input  logic rst_n,
    input  logic mem_req_valid,
    output logic mem_req_ready,
    input  pkg::l2_llc_req_t mem_req,


    // RESPONSE TO L2 / MSHR
    output logic mem_resp_valid,
    input  logic mem_resp_ready,
    output pkg::l2_llc_resp_t mem_resp
);

    // PARAMETERS
    localparam int LINE_BYTES  = LINE_BITS / 8;
    localparam int OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int INDEX_BITS  = $clog2(MEM_LINES);
    localparam int PTR_W       = (MAX_OUTSTANDING <= 1) ? 1 : $clog2(MAX_OUTSTANDING);

    logic [LINE_BITS-1:0] memory [MEM_LINES];


    logic [TAG_BITS-1:0]   slot_tag      [MAX_OUTSTANDING];
    logic [LINE_BITS-1:0]  slot_wdata    [MAX_OUTSTANDING];
    logic [LINE_BYTES-1:0] slot_wmask    [MAX_OUTSTANDING];
    pkg::l2_llc_req_op_t   slot_op       [MAX_OUTSTANDING];
    logic [ADDR_BITS-1:0]  slot_addr     [MAX_OUTSTANDING];
    logic [INDEX_BITS-1:0] slot_index    [MAX_OUTSTANDING];
    logic [LINE_BITS-1:0]  slot_rdata    [MAX_OUTSTANDING]; // captured read result (valid once slot_cnt==0)
    logic                  slot_occupied [MAX_OUTSTANDING];
    int unsigned           slot_cnt      [MAX_OUTSTANDING]; // cycles remaining; 0 = latency satisfied

    logic [PTR_W-1:0] head_ptr, tail_ptr;
    int unsigned       outstanding_count;

    logic accept_now;
    logic complete_now;

    assign accept_now   = mem_req_valid  && mem_req_ready;   // a new request is accepted this cycle
    assign complete_now = mem_resp_valid && mem_resp_ready;  // the head response is consumed this cycle

    assign mem_req_ready = (outstanding_count < MAX_OUTSTANDING);

    assign mem_resp_valid = slot_occupied[head_ptr] && (slot_cnt[head_ptr] == 0);

    always_comb begin
        mem_resp.tag   = slot_tag[head_ptr];
        mem_resp.error = 1'b0;
        mem_resp.valid = mem_resp_valid;
        if (slot_op[head_ptr] == pkg::LLC_REQ_READ) begin
            mem_resp.op   = pkg::LLC_RESP_FILL;
            mem_resp.data = slot_rdata[head_ptr];
        end else begin
            mem_resp.op   = pkg::LLC_RESP_WB_ACK;
            mem_resp.data = '0;
        end
    end

    initial begin

        for (int i = 0; i < MEM_LINES; i++) begin

            for (int b = 0;
                 b < LINE_BITS/32;
                 b++) begin

                memory[i][b*32 +: 32] = $urandom();

            end

        end

        $display("==========================================");
        $display(" Dummy LLC Initialized");
        $display("==========================================");
        $display("MEM_LINES       = %0d", MEM_LINES);
        $display("LINE_BITS       = %0d", LINE_BITS);
        $display("LINE_BYTES      = %0d", LINE_BYTES);
        $display("INDEX_BITS      = %0d", INDEX_BITS);
        $display("OFFSET_BITS     = %0d", OFFSET_BITS);
        $display("RESP_LATENCY    = %0d", RESP_LATENCY);
        $display("MAX_OUTSTANDING = %0d", MAX_OUTSTANDING);
        $display("==========================================");

    end

    // ---------------------------------------------------------------
    // accept path: push a new request into the tail slot
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tail_ptr <= '0;
        end else if (accept_now) begin
            slot_tag[tail_ptr]      <= mem_req.tag;
            slot_wdata[tail_ptr]    <= mem_req.wdata;
            slot_wmask[tail_ptr]    <= mem_req.wmask;
            slot_op[tail_ptr]       <= mem_req.op;
            slot_addr[tail_ptr]     <= mem_req.addr;
            slot_index[tail_ptr]    <= mem_req.addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS];
            slot_occupied[tail_ptr] <= 1'b1;
            slot_cnt[tail_ptr]      <= RESP_LATENCY;

            $display(
                "[LLC] %0t REQUEST  slot=%0d op=%0d addr=%h tag=%0d index=%0d (outstanding=%0d/%0d)",
                $time, tail_ptr, mem_req.op, mem_req.addr, mem_req.tag,
                mem_req.addr[OFFSET_BITS + INDEX_BITS - 1 : OFFSET_BITS],
                outstanding_count, MAX_OUTSTANDING
            );

            tail_ptr <= (tail_ptr == PTR_W'(MAX_OUTSTANDING-1)) ? '0 : tail_ptr + 1'b1;
        end
    end

    // ---------------------------------------------------------------
    // per-slot latency countdown + the actual memory access, done
    // independently for every occupied slot, every cycle. Because
    // completion order always equals arrival order (see comment
    // above), doing the real memory read/write here rather than at
    // presentation time is what keeps same-address ordering correct
    // even though multiple requests are in flight.
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int s = 0; s < MAX_OUTSTANDING; s++) begin
                slot_occupied[s] <= 1'b0;
                slot_cnt[s]      <= '0;
            end
        end else begin
            for (int s = 0; s < MAX_OUTSTANDING; s++) begin
                if (slot_occupied[s] && slot_cnt[s] > 0) begin
                    slot_cnt[s] <= slot_cnt[s] - 1;

                    if (slot_cnt[s] == 1) begin
                        // latency expires THIS edge -> do the real access now
                        if (slot_op[s] == pkg::LLC_REQ_READ) begin
                            slot_rdata[s] <= memory[slot_index[s]];
                            $display(
                                "[LLC] %0t READ      slot=%0d addr=%h index=%0d tag=%0d",
                                $time, s, slot_addr[s], slot_index[s], slot_tag[s]
                            );
                        end else if (slot_op[s] == pkg::LLC_REQ_WRITE_BACK) begin
                            for (int b = 0; b < LINE_BYTES; b++) begin
                                if (slot_wmask[s][b]) begin
                                    memory[slot_index[s]][b*8 +: 8] <= slot_wdata[s][b*8 +: 8];
                                end
                            end
                            $display(
                                "[LLC] %0t WRITEBACK slot=%0d addr=%h index=%0d tag=%0d",
                                $time, s, slot_addr[s], slot_index[s], slot_tag[s]
                            );
                        end else begin
                            $display(
                                "[LLC] %0t *** ERROR: unrecognized op=%0d in slot=%0d addr=%h tag=%0d ***",
                                $time, slot_op[s], s, slot_addr[s], slot_tag[s]
                            );
                        end
                    end
                end
            end

            // free the head slot once its response has been consumed
            if (complete_now) begin
                slot_occupied[head_ptr] <= 1'b0;
                $display(
                    "[LLC] %0t RESPONSE ACCEPTED slot=%0d tag=%0d op=%0d (outstanding=%0d/%0d)",
                    $time, head_ptr, mem_resp.tag, mem_resp.op, outstanding_count, MAX_OUTSTANDING
                );
            end
        end
    end
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            head_ptr          <= '0;
            outstanding_count <= '0;
        end else begin
            if (complete_now) begin
                head_ptr <= (head_ptr == PTR_W'(MAX_OUTSTANDING-1)) ? '0 : head_ptr + 1'b1;
            end
            case ({accept_now, complete_now})
                2'b10:   outstanding_count <= outstanding_count + 1;
                2'b01:   outstanding_count <= outstanding_count - 1;
                default: outstanding_count <= outstanding_count; // 2'b00 or 2'b11 -> net zero change
            endcase
        end
    end

endmodule

