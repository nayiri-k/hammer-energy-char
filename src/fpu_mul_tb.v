`timescale 1ns/10ps

/***************************
Must set WIDTH define
****************************/

// `define WIDTH 16
// `define WIDTH 32
// `define WIDTH 64


module fpu_mul_tb;

    reg clk = 0;
    always #(`CLOCK_PERIOD/2.0) clk = ~clk;

    reg rst = 0;
    reg [`WIDTH-1:0] in0, in1;
    reg in0_stb, in1_stb, out_ack;
    wire in0_ack, in1_ack, out_stb;
    wire [`WIDTH-1:0] out;

    integer file, status;

    real in0f, in1f, outf;

    fpu_mul fpu_mul_dut (
        .input_a(in0),
        .input_b(in1),
        .input_a_stb(in0_stb),
        .input_b_stb(in1_stb),
        .output_z_ack(out_ack),
        .clk(clk),
        .rst(rst),
        .output_z(out),
        .output_z_stb(out_stb),
        .input_a_ack(in0_ack),
        .input_b_ack(in1_ack)
    );

    initial begin
        // reset
        rst = 1'b1;
        in0_stb = 1'b0; in1_stb = 1'b0; out_ack = 1'b0;
        in0 = `WIDTH'b0; in1 = `WIDTH'b0;
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        
        // open test file
        $fsdbDumpfile({`"`TESTROOT`", "/output.fsdb"});
        $fsdbDumpvars("+all");
        $fsdbDumpon;

        file = $fopen({`"`TESTROOT`", "/input.txt"}, "r");
        if (file) begin
            while (!$feof(file)) begin
                // load vals
                @(negedge clk);
                status = $fscanf(file, "%b %b", in0, in1);
                if (status == 2) begin
                end else if (status == -1) begin
                    $display("Finished reading file.");
                    break;
                end else begin
                    $display("Error reading line.");
                    break;
                end
                in0_stb = 1'b1; in1_stb = 1'b1; out_ack = 1'b0;
                // wait for dut's response
                while (!out_stb) begin
                    @(posedge clk);
                end
                in0f = $bitstoshortreal(in0);
                in1f = $bitstoshortreal(in1);
                out_ack = 1'b1;
                outf = $bitstoshortreal(out);
                $display("binary: %b * %b = %b",in0,in1,out);
                $display("float: %f * %f = %f\n",in0f,in1f,outf);
            end
        end
        $fsdbDumpoff;
        $finish;

        // end        

    end

endmodule
