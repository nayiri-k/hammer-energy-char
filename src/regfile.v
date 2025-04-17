`define ADDR_WIDTH $clog2(`N)

module regfile (
    input                    clk,
    input  [`ADDR_WIDTH-1:0] R_addr,
    input                    R_en,
    output [`WIDTH-1:0]      R_data,
    input  [`ADDR_WIDTH-1:0] W_addr,
    input                    W_en,
    input  [`WIDTH-1:0]      W_data,
);

    reg [`WIDTH-1:0] regs [0:`N-1];

    // Write on rising edge
    always @(posedge clk) begin
        if (W_en)
            regs[W_addr] <= W_data;
    end

    // Asynchronous read
    assign R_data = R_en ? regs[R_addr] : {`WIDTH{1'bx}};;

endmodule