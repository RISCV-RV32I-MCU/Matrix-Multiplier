`timescale 1ns/1ps

module tb_matrix();
    reg clk;
    reg reset;
    
    // Wishbone signals
    reg [31:0] wb_adr_i;
    reg [31:0] wb_dat_i;
    wire [31:0] wb_dat_o;
    reg wb_we_i;
    reg wb_stb_i;
    wire wb_ack_o;
    
    // DMA signals
    wire dma_req;
    reg dma_ack;
    wire [31:0] dma_addr;
    reg [31:0] dma_data_i;
    wire [31:0] dma_data_o;
    wire dma_we;
    
   
    reg [31:0] received_c [0:1][0:1];
    integer error_count;

    integer i, j;
    
    // Clock generation
    always #5 clk = ~clk;
    
    // Instantiate dut
    lab4_3201 dut (
        .clk(clk),
        .reset(reset),
        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_dat_o(wb_dat_o),
        .wb_we_i(wb_we_i),
        .wb_stb_i(wb_stb_i),
        .wb_ack_o(wb_ack_o),
        .dma_req(dma_req),
        .dma_ack(dma_ack),
        .dma_addr(dma_addr),
        .dma_data_i(dma_data_i),
        .dma_data_o(dma_data_o),
        .dma_we(dma_we)
    );
    
    // Test parameters
    parameter MAT_A_ROWS = 2;
    parameter MAT_A_COLS = 3;
    parameter MAT_B_COLS = 2;
    
    // Test matrices
    reg [31:0] temp_a [0:5];
    reg [31:0] temp_b [0:5];
    reg [31:0] expected_c [0:1][0:1];
  
    
    task dma_transfer;
        input [31:0] base_addr;
        input integer matrix_select; // 0 for A, 1 for B
        input integer num_elements;
        integer i;
        begin
            for (i = 0; i < num_elements; i = i + 1) begin
                // Wait for matching DMA request
                while (!(dma_req && (dma_addr == (base_addr + (i << 2))))) 
                    @(posedge clk);
                
                // Select data source
                if (matrix_select == 0)
                    dma_data_i = temp_a[i];
                else
                    dma_data_i = temp_b[i];
                
                // Acknowledge transfer
                @(posedge clk);
                dma_ack = 1'b1;
                @(posedge clk);
                dma_ack = 1'b0;
            end
        end
    endtask
	 
	 

    // Main test sequence
    initial begin
        // Initialize signals
        clk = 0;
        reset = 1;
        wb_adr_i = 0;
        wb_dat_i = 0;
        wb_we_i = 0;
        wb_stb_i = 0;
        dma_ack = 0;
        dma_data_i = 0;
        
        // Initialize test matrices
        temp_a[0] = 1; temp_a[1] = 2; temp_a[2] = 3;
        temp_a[3] = 4; temp_a[4] = 5; temp_a[5] = 6;
        
        temp_b[0] = 7;  temp_b[1] = 8;
        temp_b[2] = 9;  temp_b[3] = 10;
        temp_b[4] = 11; temp_b[5] = 12;
        
        // Calculate expected results
        expected_c[0][0] = 1*7 + 2*9 + 3*11;
        expected_c[0][1] = 1*8 + 2*10 + 3*12;
        expected_c[1][0] = 4*7 + 5*9 + 6*11;
        expected_c[1][1] = 4*8 + 5*10 + 6*12;
        
        // Reset sequence
        #20 reset = 0;
        #10;
        
			wb_write(32'h00, 32'h0);       // Control register (reset)
			wb_write(32'h04, 32'h1000);    // Matrix A base address
			wb_write(32'h08, 32'h2000);    // Matrix B base address
			wb_write(32'h0C, 32'h3000);    // Matrix C base
			wb_write(32'h10, {16'd0, 2}); // Rows of A (M=2)
			wb_write(32'h12, {16'd0, 3}); // Columns of A (N=3)
			wb_write(32'h14, {16'd0, 2}); // Columns of B (P=2)
        
        // Start computation
        wb_write(32'h00, 32'h1);
        
        // Perform DMA transfers
			 fork
			 dma_transfer(32'h1000, 0, MAT_A_ROWS*MAT_A_COLS); // Matrix A
			 dma_transfer(32'h2000, 1, MAT_A_COLS*MAT_B_COLS); // Matrix B
		join
        
        // Wait for completion
          wait(dut.state == dut.DONE);
        
        // Verify results
        begin
            
            
            
            
            // Read results
            for (i = 0; i < MAT_A_ROWS*MAT_B_COLS; i = i + 1) begin
                wait(dma_req && dma_we);
                @(posedge clk);
                dma_ack = 1'b1;
                received_c[i/MAT_B_COLS][i%MAT_B_COLS] = dma_data_o;
                @(posedge clk);
                dma_ack = 1'b0;
            end
            
            // Compare results
            for (i = 0; i < MAT_A_ROWS; i = i + 1) begin
                for (j = 0; j < MAT_B_COLS; j = j + 1) begin
                    if (received_c[i][j] !== expected_c[i][j]) begin
                        $display("Error at C[%0d][%0d]: Exp %0d, Got %0d",
                                i, j, expected_c[i][j], received_c[i][j]);
                        error_count = error_count + 1;
                    end
                end
            end
            
            if (error_count == 0)
                $display("All results match!");
            else
                $display("Found %0d errors", error_count);
        end
        
        #100 $finish;
			#1000000 $display("Timeout! Simulation stopped.");
			$finish;
    end
    
    // Wishbone write task
    task wb_write;
        input [31:0] address;
        input [31:0] data;
        begin
            @(posedge clk);
            wb_adr_i = address;
            wb_dat_i = data;
            wb_we_i = 1'b1;
            wb_stb_i = 1'b1;
            wait(wb_ack_o);
            @(posedge clk);
            wb_stb_i = 1'b0;
            wb_we_i = 1'b0;
        end
    endtask
    
	 always @(posedge clk) begin
    if (dma_req)
        $display("[DMA] Request: addr=0x%h, we=%b, time=%t", dma_addr, dma_we, $time);
    if (dma_ack)
        $display("[DMA] Acknowledged, time=%t", $time);
	end
    // Monitor state transitions
    always @(dut.state) begin
        $display("State changed to %0d at time %0t", dut.state, $time);
    end
	 always @(posedge clk) begin
    if (dma_req) 
        $display("[TB] DMA Request: addr=0x%h, we=%b", dma_addr, dma_we);
    if (dma_ack)
        $display("[TB] DMA Acknowledged");
	end
    
    // Waveform dump
    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_matrix_accelerator);
    end
	    
    
endmodule