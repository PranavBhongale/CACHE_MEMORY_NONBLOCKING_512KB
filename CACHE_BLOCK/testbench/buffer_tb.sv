`timescale 1ns/1ps

module buffer_tb;

    typedef struct packed {
     logic [31:0] data;
    } data_t;

    parameter int DEPTH = 8 ;

    logic clk ;
    logic rst_n ;

    logic in_valid ;
    data_t in_data ;
    logic in_ready ;

    logic out_valid ;
    data_t  out_data ;
    logic  out_ready;

   initial begin
     rst_n = 0 ;
     #30;
     @(posedge clk );
     rst_n = 1 ;
   end

task automatic  push (data_t data );
    wait(in_ready);
    if(in_ready) begin
        in_data = data ;
        in_valid = 1'd1;
        @(posedge clk );
        in_valid = 1'd0 ;

    end
endtask

data_t  monitor_data ;

task automatic  pop();
  out_ready = 1'd1 ;
  wait(out_valid);
   if(out_valid)begin
    $display("output data is %0h", out_data.data);
   end
    @(posedge clk )
 out_ready = 1'd0;

endtask //automatic
initial clk = 0;
always #5 clk = ~clk ;

// connection to the BUFFER module

        buffer #(
        .T(data_t),
        .DEPTH(DEPTH)
        )dut (

        .clk(clk),
        .rst_n(rst_n),

        // input interface
        .in_valid(in_valid),
        .in_data(in_data),
        .in_ready(in_ready),

        // output interface
        .out_valid(out_valid),
        .out_data(out_data),
        .out_ready(out_ready)
        );


initial begin

    data_t tx;

    tx.data = 100;

    push(tx);
    @(posedge clk );

    repeat (20)
    @(posedge clk);

    pop();
     tx.data = 200;
    push(tx);

   pop();
   for( int  i = 0 ; i <= 7  ; i++)begin
       tx.data = i ;
       push(tx);
   end

   pop();
   pop();
   pop();
   pop();
   pop();
   pop();
   pop();
   pop();
   pop();

end



initial begin
    $dumpfile("wave.vcd");
    $dumpvars( 0 , buffer_tb);
end

initial begin
#650;
$finish;
end

endmodule


