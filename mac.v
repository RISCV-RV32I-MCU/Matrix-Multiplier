module mac_unit (
    input wire clk,
    input wire reset,
    input wire clear,    // Clear accumulator
    input wire enable,   // Computation enable
    input wire [31:0] a_in,
    input wire [31:0] b_in,
    output wire [31:0] accum_out
);

reg [31:0] accumulator;

always @(posedge clk) begin
    if (reset || clear) begin
        accumulator <= 32'd0;
    end else if (enable) begin
        accumulator <= accumulator + (a_in * b_in);
    end
end

assign accum_out = accumulator;
endmodule