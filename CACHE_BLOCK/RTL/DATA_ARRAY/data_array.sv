`timescale 1ns/1ps

module data_array #(
    parameter int CACHE_SETS = 2048,
    parameter int CACHE_WAYS = 4,
    parameter int LINE_BITS  = 512
)(

    // Clock / Reset
    input  logic clk,
    input  logic rst_n,

    // Read Port
    input  logic                  rd_en,
    input  logic [10:0]           rd_set,
    input  logic [1:0]            rd_way,

    output logic [LINE_BITS-1:0]  rd_data,
    output logic                  rd_valid,
    output logic                  rd_dirty,

    // Write Port
    input  logic                  wr_en,
    input  logic [10:0]           wr_set,
    input  logic [1:0]            wr_way,

    input  logic [LINE_BITS-1:0]  wr_data,
    input  logic                  wr_valid,
    input  logic                  wr_dirty
);


    // Memory Arrays
    logic [LINE_BITS-1:0] mem   [CACHE_SETS][CACHE_WAYS];
    logic                 valid [CACHE_SETS][CACHE_WAYS];
    logic                 dirty [CACHE_SETS][CACHE_WAYS];

    // Combinational Read
    always_comb begin

        // Default values
        rd_data  = '0;
        rd_valid = 1'b0;
        rd_dirty = 1'b0;

        if (rst_n && rd_en) begin
            rd_data  = mem[rd_set][rd_way];
            rd_valid = valid[rd_set][rd_way];
            rd_dirty = dirty[rd_set][rd_way];
        end

    end
    // Synchronous Write / Reset
    always_ff @(posedge clk) begin : WRITE_DATA

        integer set;
        integer way;

        if (!rst_n) begin

            for (set = 0; set < CACHE_SETS; set++) begin
                for (way = 0; way < CACHE_WAYS; way++) begin
                    mem[set][way]   <= '0;
                    valid[set][way] <= 1'b0;
                    dirty[set][way] <= 1'b0;
                end
            end

        end
        else if (wr_en) begin

            mem[wr_set][wr_way]   <= wr_data;
            valid[wr_set][wr_way] <= wr_valid;
            dirty[wr_set][wr_way] <= wr_dirty;

        end

    end

endmodule
