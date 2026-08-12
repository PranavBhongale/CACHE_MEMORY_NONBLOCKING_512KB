

//  this store the tag only

module tag_memory #(
    parameter int TM_NUM_SETS = 2048,
    parameter int TM_NUM_WAYS = 4,
    parameter int TM_INDEX_BITS = 11 ,
    parameter int TM_OFFSET_BITS = 6 ,
    parameter int TM_ADDR_BITS = 64 ,
    parameter int TM_TAG_BITS = TM_ADDR_BITS - TM_INDEX_BITS - TM_OFFSET_BITS
)(
    input logic clk,
    input logic rst_n,


    // input 
    input logic tag_read_enable,
    input logic [TM_INDEX_BITS-1:0] tag_index, //  shared index for read and write


    output logic [TM_TAG_BITS-1:0] tag_way0,
    output logic [TM_TAG_BITS-1:0] tag_way1,
    output logic [TM_TAG_BITS-1:0] tag_way2,
    output logic [TM_TAG_BITS-1:0] tag_way3,


    output logic [TM_NUM_WAYS -1 : 0 ]tag_valid ,
    input logic write_enable,
    input logic [TM_NUM_WAYS-1:0] write_way,
    input logic [TM_TAG_BITS-1:0] write_tag
);

 
    logic [TM_TAG_BITS-1:0] tag_table [TM_NUM_SETS][TM_NUM_WAYS];
    logic  valid_table [TM_NUM_SETS][TM_NUM_WAYS];


    // read logic
    always_comb begin : tag_read
        if(tag_read_enable) begin
            tag_way0 = tag_table[tag_index][0];
            tag_way1 = tag_table[tag_index][1];
            tag_way2 = tag_table[tag_index][2];
            tag_way3 = tag_table[tag_index][3];

            // valid logic
            tag_valid[0] = valid_table[tag_index][0];
            tag_valid[1] = valid_table[tag_index][1];
            tag_valid[2] = valid_table[tag_index][2];
            tag_valid[3] = valid_table[tag_index][3];

        end else begin
            tag_way0 = '0;
            tag_way1 = '0;
            tag_way2 = '0;
            tag_way3 = '0;
            tag_valid = 4'b0;
        end
    end

    // combinational read and siquential write logic
    always_ff @(posedge clk) begin : tag_memory
        if(!rst_n) begin
            for(int i = 0 ; i < TM_NUM_SETS ; i++) begin
                for(int j = 0 ; j < TM_NUM_WAYS ; j++) begin
                    tag_table[i][j] <= '0;
                    valid_table[i][j] <= 1'b0;
                end
            end
        end else begin
            if(write_enable) begin
                for(int j = 0 ; j < TM_NUM_WAYS ; j++) begin
                    if(write_way[j]) begin
                        tag_table[tag_index][j] <= write_tag;
                        valid_table[tag_index][j] <= 1'b1;
                    end
                end
            end
        end
    end

endmodule

