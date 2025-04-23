//--------------------------------------------------
// Matrix Accelerator
//--------------------------------------------------
module matrix (
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

reg [31:0] ctrl_reg;          // Control register
reg [31:0] status_reg;        // Status register
reg [31:0] matrix_a_addr;     // Matrix A base address
reg [31:0] matrix_b_addr;     // Matrix B base address
reg [31:0] matrix_c_addr;     // Matrix C result address
reg [15:0] matrix_rows;    // Rows of A (M)
reg [15:0] matrix_a_cols;  // Columns of A = Rows of B (N)
reg [15:0] matrix_cols;    // Columns of B (P)
reg computation_done; // Flag to indicate computation done
//reg [31:0] load_counter_a, load_counter_b;

//  Configuration Parameters
parameter MAT_SIZE = 3;       // 8x8 matrix
parameter DATA_WIDTH = 32;    // 32-bit data
parameter MAC_UNITS = 3;      // Number of parallel MAC units

// Add these new declarations
reg [15:0] row_counter;    // Current row in matrix A
reg [15:0] col_counter;    // Current column in matrix B
reg [15:0] dot_counter;    // Dot product element counter
						
parameter IDLE        = 3'd0;
parameter LOAD_MATRICES = 3'd1;
parameter COMPUTE     = 3'd2;
parameter STORE_RESULTS = 3'd3;
parameter DONE        = 3'd4;

reg [2:0] state;
// MAC Unit Connections
wire [31:0] mac_accumulator [0:MAC_UNITS-1];
wire mac_clear;
wire mac_enable;

reg [DATA_WIDTH-1:0] a_buffer [0:MAT_SIZE-1][0:MAT_SIZE-1];
reg [DATA_WIDTH-1:0] b_buffer [0:MAT_SIZE-1][0:MAT_SIZE-1];
reg [DATA_WIDTH-1:0] c_buffer [0:MAT_SIZE-1][0:MAT_SIZE-1];

// DMA Control Signals
reg [31:0] load_counter;      // Tracks elements loaded for A/B
reg [31:0] store_counter;     // Tracks elements stored for C
reg loading_matrix_a;         // Flag for which matrix is being loaded
assign dma_req = (state == LOAD_MATRICES || state == STORE_RESULTS);
assign dma_we = (state == STORE_RESULTS); // Write-enable only during store

// Address calculation logic
wire [31:0] matrix_a_offset = matrix_a_addr + (load_counter << 2);  // Multiply by 4 (byte address)
wire [31:0] matrix_b_offset = matrix_b_addr + (load_counter << 2);
wire [31:0] matrix_c_offset = matrix_c_addr + (store_counter << 2);

assign dma_addr = (state == LOAD_MATRICES) ? 
                    (loading_matrix_a ? matrix_a_offset : matrix_b_offset) :
                  (state == STORE_RESULTS) ? matrix_c_offset :
                  32'h0;  // Default address

reg [31:0] mac_sum; // Declare mac_sum here
integer k;
						
always @* begin
    mac_sum = 0;
    for (k = 0; k < MAC_UNITS; k = k + 1) begin
        mac_sum = mac_sum + mac_accumulator[k];
    end
end

//--------------------------------------------------
// MAC Unit Array Instantiation
//--------------------------------------------------
generate
    genvar i;
    for (i = 0; i < MAC_UNITS; i = i + 1) begin : mac_array
        mac mac_inst (
            .clk(clk),
            .reset(reset),
            .clear(mac_clear),
            .enable(mac_enable),
            .a_in(a_buffer[row_counter][(dot_counter + i) % MAT_SIZE]),
				.b_in(b_buffer[(dot_counter + i) % MAT_SIZE][col_counter]),
            .accum_out(mac_accumulator[i])
        );
    end
endgenerate

//--------------------------------------------------
// MAC Control Signals
//--------------------------------------------------
assign mac_clear = (state == COMPUTE) && (dot_counter == 0);
assign mac_enable = (state == COMPUTE);

//--------------------------------------------------
// Computation Logic (Single Source of Truth)
always @(posedge clk) begin
    if (reset) begin
        row_counter <= 0;
        col_counter <= 0;
        dot_counter <= 0;
        computation_done <= 0;
    end else if (state == COMPUTE) begin
        if (dot_counter < matrix_a_cols) begin
            // Process up to MAC_UNITS elements per cycle
            dot_counter <= dot_counter + MAC_UNITS;
            if (dot_counter + MAC_UNITS > matrix_a_cols) begin
                dot_counter <= matrix_a_cols; // Handle partial
            end
        end else begin
            // Final accumulation
            dot_counter <= 0;
            c_buffer[row_counter][col_counter] <= mac_sum;

            // Update indices
            if (col_counter < (matrix_cols - 1)) begin
                col_counter <= col_counter + 1;
            end else begin
                col_counter <= 0;
                if (row_counter < (matrix_rows - 1)) begin
                    row_counter <= row_counter + 1;
                end else begin
                    computation_done <= 1;
                end
            end
        end
    end else begin
        computation_done <= 0;
    end
end
//--------------------------------------------------
// DMA Data Handling (Updated)
//--------------------------------------------------
assign dma_data_o = c_buffer[store_counter / matrix_cols]
                      [store_counter % matrix_cols];
							 
// During loading phase
always @(posedge clk) begin
    if (dma_ack && (state == LOAD_MATRICES)) begin
        if (loading_matrix_a) begin
           a_buffer[load_counter / matrix_a_cols]
						[load_counter % matrix_a_cols] <= dma_data_i;
        end else begin
           b_buffer[load_counter / matrix_cols]
						[load_counter % matrix_cols] <= dma_data_i;
        end
    end
end


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
        matrix_a_cols <= 0;  // Add this reset
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
                    8'h12: matrix_a_cols <= wb_dat_i[15:0];  
                    8'h14: matrix_cols <= wb_dat_i[15:0];    
                endcase
            end else begin
                // Register reads
                case (wb_adr_i[7:0])
                    8'h00: wb_dat_o <= ctrl_reg;
                    8'h04: wb_dat_o <= matrix_a_addr;
                    8'h08: wb_dat_o <= matrix_b_addr;
                    8'h0C: wb_dat_o <= matrix_c_addr;
                    8'h10: wb_dat_o <= {16'b0, matrix_rows};
                    8'h12: wb_dat_o <= {16'b0, matrix_a_cols};  
                    8'h14: wb_dat_o <= {16'b0, matrix_cols};
                    8'h16: wb_dat_o <= status_reg;
                    default: wb_dat_o <= 32'hDEADBEEF;
                endcase
            end
        end else begin
            wb_ack_o <= 0;
        end
    end
end



//--------------------------------------------------
// Main State Machine
//--------------------------------------------------
always @(posedge clk) begin

    if (reset) begin
        state <= IDLE;
        status_reg <= 0;
    end else begin
        case (state)
            IDLE: begin
					 if (ctrl_reg[0]) begin
						  state <= LOAD_MATRICES;
						  loading_matrix_a <= 1;  // Initialize to load Matrix A
						  load_counter <= 0;      // Reset counter
						  status_reg <= 1;        // Busy flag
					 end
				end
            
           LOAD_MATRICES: begin
					 if (dma_ack) begin
					     $display("[LOAD] Counter=%0d, Matrix=%s, Time=%0t",
							load_counter, 
							loading_matrix_a ? "A" : "B", 
							$time
					  );
						  if (loading_matrix_a) begin
								// Matrix A: rows × a_cols elements
								if (load_counter == (matrix_rows * matrix_a_cols - 1)) begin
									 loading_matrix_a <= 0;
									 load_counter <= 0;
								end else begin
									 load_counter <= load_counter + 1;
								end
						  end else begin
								// Matrix B: a_cols × cols elements
								if (load_counter == (matrix_a_cols * matrix_cols - 1)) begin
									 state <= COMPUTE;
									 load_counter <= 0;
								end else begin
									 load_counter <= load_counter + 1;
								end
						  end
					 end
				end

            COMPUTE: begin
		$display("[COMPUTE] row=%0d, col=%0d, dot_counter=%0d", 
                  row_counter, col_counter, dot_counter);
                // Perform matrix multiplication using MAC units
                if (computation_done == 1) begin
                    state <= STORE_RESULTS;
                    // Removed the line that resets computation_done here
                end
            end
            
            STORE_RESULTS: begin
                // Check if all results are stored
                if (dma_ack && (store_counter == (matrix_rows * matrix_cols - 1))) begin
                    state <= DONE;
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
always @(posedge clk) begin
    if (computation_done)
        $display("[DESIGN] Computation done at time %t", $time);
end

always @(posedge clk) begin
    if (reset) begin
        store_counter <= 0;
    end else if (state == STORE_RESULTS && dma_ack) begin
        store_counter <= store_counter + 1;
    end
end							 
							 
endmodule


