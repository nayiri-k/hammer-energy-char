`timescale 1ns/10ps
`define ADDR_WIDTH $clog2(`N)

module regfile_tb;

    reg clk = 0;
    always #(`CLOCK_PERIOD/2.0) clk = ~clk;

    reg [`ADDR_WIDTH-1:0] R_addr;
    reg                 R_en;
    reg [`WIDTH-1:0]      R_data;
    reg [`ADDR_WIDTH-1:0] W_addr;
    reg                   W_en;
    reg [`WIDTH-1:0]      W_data;

    integer file, status;

    regfile regfile_dut (
        .clk(clk),
        .R_addr(R_addr),
        .R_en(R_en),
        .R_data(R_data),
        .W_addr(W_addr),
        .W_en(W_en),
        .W_data(W_data)
    );

    initial begin
        // reset
        R_addr = 1'b0;
        W_addr = 1'b0;
        R_en = 1'b0;
        W_en = 1'b0;
        W_data = 1'b0;
        @(negedge clk);
        
        // open test file
        $fsdbDumpfile({`"`TESTROOT`", "/output.fsdb"});
        $fsdbDumpvars("+all");
        $fsdbDumpon;

        file = $fopen({`"`TESTROOT`", "/input.txt"}, "r");
        if (file) begin
            while (!$feof(file)) begin
                // load vals
                status = $fscanf(file, "%b %b %b %b %b\n", R_en, R_addr, W_en, W_addr, W_data);
                if (status == 5) begin
                end else if (status == -1) begin
                    $display("Finished reading file.");
                end else begin
                    $display("Error reading line.");
                end
                // perform operation
                @(posedge clk);
                @(negedge clk);
                $display("Performed the following operation: %b, %b, %b, %b, %b", R_en, R_addr, W_en, W_addr, W_data);
            end
        end
        $fsdbDumpoff;
        $finish;

        // end        

    end

endmodule