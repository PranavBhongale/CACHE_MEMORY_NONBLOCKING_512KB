// tag_compare module
// in this module we have to do just tag compare
// not more than this

module tag_compare  #(
    parameter int TC_NUM_WAYS = 4,
    parameter int TC_TAG_BITS = 47
)(
    input logic tag_valid,
    input logic [TC_TAG_BITS-1:0] req_tag,
    input logic [TC_TAG_BITS-1 : 0 ] tag_way0,
    input logic [TC_TAG_BITS-1 : 0 ] tag_way1,
    input logic [TC_TAG_BITS-1 : 0 ] tag_way2,
    input logic [TC_TAG_BITS-1 : 0 ] tag_way3,
    output logic hit,
    output logic [1:0] hit_way ,
    output logic miss
);

// combinational tag compare logic
always_comb begin : tag_compare
   hit = 0 ;
   hit_way = 0 ;
   miss = 0 ;
   if(tag_valid) begin 
     if(req_tag == tag_way0)begin
        hit = 1'b1;
        hit_way = 2'b00;
     end else if( req_tag == tag_way1)begin
        hit = 1'b1;
        hit_way = 2'b01;
     end else if (req_tag == tag_way2 ) begin
        hit = 1'b1;
        hit_way = 2'b10;
     end else if ( req_tag == tag_way3 ) begin
        hit = 1'b1;
        hit_way = 2'b11;
     end else begin
        miss = 1'b1;
        hit = 1'b0;
     end
   end
end

endmodule
