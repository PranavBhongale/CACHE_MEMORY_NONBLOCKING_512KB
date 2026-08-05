`timescale 1ns/1ps

module buffer #(
    parameter type T = logic [31:0],
    parameter int DEPTH = 8
)(
    input  logic clk,
    input  logic rst_n,


    // Input Interface
    input  logic in_valid,
    input  T     in_data,
    output logic in_ready,


    // Output Interface
    output logic out_valid,
    output T     out_data,
    input  logic out_ready
);

    // Parameters
    localparam int PTRW = (DEPTH <= 2) ? 1 : $clog2(DEPTH);

    // Memory
    T mem [DEPTH];

    // State
    logic [PTRW-1:0] wr_ptr;
    logic [PTRW-1:0] rd_ptr;
    logic [$clog2(DEPTH+1)-1:0] count;

    logic push , pop ;

    assign push = in_valid && (count < 4'(DEPTH));
    assign pop = out_ready && (count > 0 );

    always_ff @( posedge clk  ) begin : process
        if(!rst_n)begin
          count <= 0;
          wr_ptr <= 0 ;
          rd_ptr <= 0 ;
        end else begin
                if(push) begin
                    mem[wr_ptr] <= in_data ;
                    if(wr_ptr == 3'(DEPTH-1) ) begin
                        wr_ptr <= 0 ;
                    end else begin
                    wr_ptr <= wr_ptr + 1;
                    end
                end
     if(pop)begin
        if(rd_ptr == 3'(DEPTH -1 ) ) begin
            rd_ptr <= 0 ;
        end else begin
            rd_ptr <= rd_ptr + 1 ;
        end
     end

     if(push && !pop ) begin
        count <= count + 1 ;
     end else if ( pop && ! push )begin
        count <= count - 1 ;
     end

     if((count > 0) && out_ready) begin
        out_valid <= 1'b1;
        out_data <= mem[rd_ptr];
     end else begin
        out_valid <= 1'b0;
     end
    end

end

  always_comb begin : reset
   if(rst_n)begin 
   in_ready = (count < 4'(DEPTH) );
   end else begin
    in_ready = 0 ;
   end
  end

endmodule
