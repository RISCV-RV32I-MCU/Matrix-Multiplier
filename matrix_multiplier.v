module matrix_multiplier (
    input logic clk,
    input logic reset,
    input logic [15:0] matrix_a_address,
    input logic [15:0] matrix_b_address,
    output logic [15:0] result
);
    // this is how to Multiply using LUT you can also just leave it as it is and it will use LUT
    // (* keep *) logic [15:0] result;
    // assign result = a * b;  

    // this is how to Multiply using DSP
    // (* multstyle = "dsp" *) logic [15:0] result;
    // assign result = a * b;

    

endmodule