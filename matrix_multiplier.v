// Matrix Multiplier Accelerator
module matrix_accelerator (
    input wire clk, // switch to DE10-CLK
    input wire reset, // Make sure this is the correct reset signal
    
    // Wishbone Bus Interface (CPU side) // Check with the PM and bosses to ensure this interface is okkay
    input wire [31:0] wb_adr_i,
    input wire [31:0] wb_dat_i,
    output reg [31:0] wb_dat_o,
    input wire wb_we_i,
    input wire wb_stb_i,
    output reg wb_ack_o,
    
    // DMA Interface
    output wire dma_req,
    input wire dma_ack,
    output wire [31:0] dma_addr,
    input wire [31:0] dma_data_i,
    output wire [31:0] dma_data_o,
    output wire dma_we
);

// Configuration Parameters
parameter MAT_SIZE = 8;       // 8x8 matrix
parameter DATA_WIDTH = 32;    // 32-bit data
parameter MAC_UNITS = 8;      // Number of parallel MAC units

// Control Registers
reg [31:0] ctrl_reg;          // Control register
reg [31:0] status_reg;        // Status register
reg [31:0] matrix_a_addr;     // Matrix A base address
reg [31:0] matrix_b_addr;     // Matrix B base address
reg [31:0] matrix_c_addr;     // Matrix C result address
reg [15:0] matrix_rows;       // Matrix dimensions
reg [15:0] matrix_cols;
reg computation_done; // Flag to indicate computation done

// Internal Signals
reg [DATA_WIDTH-1:0] a_buffer [0:MAT_SIZE-1][0:MAT_SIZE-1];
reg [DATA_WIDTH-1:0] b_buffer [0:MAT_SIZE-1][0:MAT_SIZE-1];
reg [DATA_WIDTH-1:0] c_buffer [0:MAT_SIZE-1][0:MAT_SIZE-1];

// DMA Control Signals
reg [31:0] load_counter;      // Tracks elements loaded for A/B
reg [31:0] store_counter;     // Tracks elements stored for C
reg loading_matrix_a;         // Flag for which matrix is being loaded

// Address calculation logic
wire [31:0] matrix_a_offset = matrix_a_addr + (load_counter << 2);  // Multiply by 4 (byte address)
wire [31:0] matrix_b_offset = matrix_b_addr + (load_counter << 2);
wire [31:0] matrix_c_offset = matrix_c_addr + (store_counter << 2);

assign dma_addr = (state == LOAD_MATRICES) ? 
                    (loading_matrix_a ? matrix_a_offset : matrix_b_offset) :
                  (state == STORE_RESULTS) ? matrix_c_offset :
                  32'h0;  // Default address

// FSM States
typedef enum {
    IDLE,
    LOAD_MATRICES,
    COMPUTE,
    STORE_RESULTS,
    DONE
} state_t;
reg [2:0] state;

// MAC Units
genvar i;
generate
    for (i = 0; i < MAC_UNITS; i = i + 1) begin : mac_array
        // Instantiate MAC units here
        // Each MAC unit would contain multiplier and accumulator
    end
endgenerate

// Wishbone Interface
always @(posedge clk) begin
    if (reset) begin
        wb_dat_o <= 0;
        wb_ack_o <= 0;
        // Reset control registers
        ctrl_reg <= 0;
        matrix_a_addr <= 0;
        matrix_b_addr <= 0;
        matrix_c_addr <= 0;
        matrix_rows <= 0;
        matrix_cols <= 0;
    end else begin
        if (wb_stb_i && !wb_ack_o) begin
            wb_ack_o <= 1;
            if (wb_we_i) begin
                // Register writes
                case (wb_adr_i[7:0])
                    8'h00: ctrl_reg <= wb_dat_i;
                    8'h04: matrix_a_addr <= wb_dat_i;
                    8'h08: matrix_b_addr <= wb_dat_i;
                    8'h0C: matrix_c_addr <= wb_dat_i;
                    8'h10: matrix_rows <= wb_dat_i[15:0];
                    8'h12: matrix_cols <= wb_dat_i[15:0];
                endcase
            end else begin
                // Register reads
                case (wb_adr_i[7:0])
                    8'h00: wb_dat_o <= ctrl_reg;
                    8'h04: wb_dat_o <= matrix_a_addr;
                    8'h08: wb_dat_o <= matrix_b_addr;
                    8'h0C: wb_dat_o <= matrix_c_addr;
                    8'h10: wb_dat_o <= {16'b0, matrix_rows};
                    8'h12: wb_dat_o <= {16'b0, matrix_cols};
                    8'h14: wb_dat_o <= status_reg;
                    default: wb_dat_o <= 32'hDEADBEEF;
                endcase
            end
        end else begin
            wb_ack_o <= 0;
        end
    end
end

// DMA Control Logic
assign dma_req = (state == LOAD_MATRICES) || (state == STORE_RESULTS);
assign dma_we = (state == STORE_RESULTS);
assign dma_addr = 0; /* Calculate current address based on state also ask Shoib if this is okay*/

// Counter control logic
always @(posedge clk) begin
    if (reset) begin
        load_counter <= 0;
        store_counter <= 0;
        loading_matrix_a <= 1;
    end else begin
        case(state)
            LOAD_MATRICES: begin
                if (dma_ack) begin
                    if (loading_matrix_a) begin
                        // Check if we've loaded all elements of A
                        if (load_counter == (matrix_rows * matrix_cols - 1)) begin
                            loading_matrix_a <= 0;
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end else begin
                        // Loading matrix B
                        if (load_counter == (matrix_cols * matrix_rows - 1)) begin
                            load_counter <= 0;
                        end else begin
                            load_counter <= load_counter + 1;
                        end
                    end
                end
            end
            
            STORE_RESULTS: begin
                if (dma_ack) begin
                    store_counter <= store_counter + 1;
                end
            end
            
            default: begin
                load_counter <= 0;
                store_counter <= 0;
                loading_matrix_a <= 1;
            end
        endcase
    end
end
// Main State Machine
always @(posedge clk) begin
    if (reset) begin
        state <= IDLE;
        status_reg <= 0;
    end else begin
        case (state)
            IDLE: begin
                if (ctrl_reg[0]) begin  // Start bit
                    state <= LOAD_MATRICES;
                    status_reg <= 1;    // Busy flag
                end
            end
            
           LOAD_MATRICES: begin
                // Check if both matrices are loaded
                if (!loading_matrix_a && dma_ack && (load_counter == (matrix_cols * matrix_rows - 1))) begin
                    state <= COMPUTE;
                end
            end
        
            STORE_RESULTS: begin
                // Check if all results are stored
                if (dma_ack && (store_counter == (matrix_rows * matrix_rows - 1))) begin
                    state <= DONE;
                end
            end
            COMPUTE: begin
                // Perform matrix multiplication using MAC units
                if (computation_done == 1) begin
                    state <= STORE_RESULTS;
                    computation_done <= 0; // Reset the flag
                end
            end
            
            DONE: begin
                status_reg <= 2;        // Done flag
                if (!ctrl_reg[0]) begin // Clear start bit
                    state <= IDLE;
                    status_reg <= 0;
                end
            end
        endcase
    end
end

// // Matrix Computation Logic
// always @(posedge clk) begin
//     if (state == COMPUTE) begin

//         // Implement parallel dot product computation
//         // using the instantiated MAC units
//         // This would include nested loops for matrix multiplication
//         // with pipelined operations
//         // computation_done <= 1; // Set this flag when computation is done
//     end
//end

endmodule