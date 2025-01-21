//IEEE Floating Point Adder (Single Precision)
//Copyright (C) Jonathan P Dawson 2013
//2013-12-12

`ifdef FPU8
`define WIDTH 8
`define EXPONENT 4
`define MANTISSA 3
`define EXP_MIN -6
`define EXP_MAX  7
`endif // FPU8

`ifdef FPU16
`define WIDTH 16
`define EXPONENT 5
`define MANTISSA 11
`define EXP_MIN -14
`define EXP_MAX  15
`endif // FPU16

`ifdef FPU32
`define WIDTH 32
`define EXPONENT 8
`define MANTISSA 23
`define EXP_MIN -126
`define EXP_MAX  127
`endif // FPU32

`ifdef FPU64
`define WIDTH 64
`define EXPONENT 11
`define MANTISSA 52
`define EXP_MIN -1022
`define EXP_MAX  1023
`endif // FPU64

// derived defines
`define SB `WIDTH-1
`define EHB `WIDTH-2
`define ELB `MANTISSA
`define MHB `MANTISSA-1
`define EXP_MAXVAL ((1 << `EXPONENT) - 1)
`define MTS_MAXVAL ((1 << (`MANTISSA+1)) - 1)
`define EXPBITS `EHB:`ELB
`define MTSBITS `MHB:0

module fpu_adder(
        input_a,
        input_b,
        input_a_stb,
        input_b_stb,
        output_z_ack,
        clk,
        rst,
        output_z,
        output_z_stb,
        input_a_ack,
        input_b_ack);

  input     clk;
  input     rst;

  input     [`WIDTH-1:0] input_a;
  input     input_a_stb;
  output    input_a_ack;

  input     [`WIDTH-1:0] input_b;
  input     input_b_stb;
  output    input_b_ack;

  output    [`WIDTH-1:0] output_z;
  output    output_z_stb;
  input     output_z_ack;

  reg       s_output_z_stb;
  reg       [`WIDTH-1:0] s_output_z;
  reg       s_input_a_ack;
  reg       s_input_b_ack;

  reg       [3:0] state;
  parameter get_a         = 4'd0,
            get_b         = 4'd1,
            unpack        = 4'd2,
            special_cases = 4'd3,
            align         = 4'd4,
            add_0         = 4'd5,
            add_1         = 4'd6,
            normalise_1   = 4'd7,
            normalise_2   = 4'd8,
            round         = 4'd9,
            pack          = 4'd10,
            put_z         = 4'd11;

  reg       [`WIDTH-1:0] a, b, z;
  reg       [`MANTISSA+3:0] a_m, b_m;
  reg       [`MANTISSA:0] z_m;
  reg       [`EXPONENT+1:0] a_e, b_e, z_e;
  reg       a_s, b_s, z_s;
  reg       guard, round_bit, sticky;
  reg       [`MANTISSA+4:0] sum;

  always @(posedge clk)
  begin

    case(state)

      get_a:
      begin
        s_input_a_ack <= 1;
        if (s_input_a_ack && input_a_stb) begin
          a <= input_a;
          s_input_a_ack <= 0;
          state <= get_b;
        end
      end

      get_b:
      begin
        s_input_b_ack <= 1;
        if (s_input_b_ack && input_b_stb) begin
          b <= input_b;
          s_input_b_ack <= 0;
          state <= unpack;
        end
      end

      unpack:
      begin
        a_m <= {a[`MTSBITS], 3'd0};
        b_m <= {b[`MTSBITS], 3'd0};
        a_e <= a[`EXPBITS] - `EXP_MAX;
        b_e <= b[`EXPBITS] - `EXP_MAX;
        a_s <= a[`WIDTH-1];
        b_s <= b[`WIDTH-1];
        state <= special_cases;
      end

      special_cases:
      begin
        //if a is NaN or b is NaN return NaN 
        if ((a_e == (`EXP_MAX+1) && a_m != 0) || (b_e == (`EXP_MAX+1) && b_m != 0)) begin
          z[`WIDTH-1] <= 1;
          z[`EXPBITS] <= `EXP_MAXVAL;
          z[`MHB] <= 1;
          z[`MHB-1:0] <= 0;
          state <= put_z;
        //if a is inf return inf
        end else if (a_e == (`EXP_MAX+1)) begin
          z[`WIDTH-1] <= a_s;
          z[`EXPBITS] <= `EXP_MAXVAL;
          z[`MTSBITS] <= 0;
          //if a is inf and signs don't match return nan
          if ((b_e == (`EXP_MAX+1)) && (a_s != b_s)) begin
              z[`WIDTH-1] <= b_s;
              z[`EXPBITS] <= `EXP_MAXVAL;
              z[`MHB] <= 1;
              z[`MHB-1:0] <= 0;
          end
          state <= put_z;
        //if b is inf return inf
        end else if (b_e == (`EXP_MAX+1)) begin
          z[`WIDTH-1] <= b_s;
          z[`EXPBITS] <= `EXP_MAXVAL;
          z[`MTSBITS] <= 0;
          state <= put_z;
        //if a is zero return b
        end else if ((($signed(a_e) == -`EXP_MAX) && (a_m == 0)) && (($signed(b_e) == -`EXP_MAX) && (b_m == 0))) begin
          z[`WIDTH-1] <= a_s & b_s;
          z[`EXPBITS] <= b_e[`EXPONENT-1:0] + `EXP_MAX;
          z[`MTSBITS] <= b_m[`MANTISSA+3:3];
          state <= put_z;
        //if a is zero return b
        end else if (($signed(a_e) == -`EXP_MAX) && (a_m == 0)) begin
          z[`WIDTH-1] <= b_s;
          z[`EXPBITS] <= b_e[`EXPONENT-1:0] + `EXP_MAX;
          z[`MTSBITS] <= b_m[`MANTISSA+3:3];
          state <= put_z;
        //if b is zero return a
        end else if (($signed(b_e) == -`EXP_MAX) && (b_m == 0)) begin
          z[`WIDTH-1] <= a_s;
          z[`EXPBITS] <= a_e[`EXPONENT-1:0] + `EXP_MAX;
          z[`MTSBITS] <= a_m[`MANTISSA+3:3];
          state <= put_z;
        end else begin
          //Denormalised Number
          if ($signed(a_e) == -`EXP_MAX) begin
            a_e <= `EXP_MIN;
          end else begin
            a_m[`MANTISSA+3] <= 1;
          end
          //Denormalised Number
          if ($signed(b_e) == -`EXP_MAX) begin
            b_e <= `EXP_MIN;
          end else begin
            b_m[`MANTISSA+3] <= 1;
          end
          state <= align;
        end
      end

      align:
      begin
        if ($signed(a_e) > $signed(b_e)) begin
          b_e <= b_e + 1;
          b_m <= b_m >> 1;
          b_m[0] <= b_m[0] | b_m[1];
        end else if ($signed(a_e) < $signed(b_e)) begin
          a_e <= a_e + 1;
          a_m <= a_m >> 1;
          a_m[0] <= a_m[0] | a_m[1];
        end else begin
          state <= add_0;
        end
      end

      add_0:
      begin
        z_e <= a_e;
        if (a_s == b_s) begin
          sum <= a_m + b_m;
          z_s <= a_s;
        end else begin
          if (a_m >= b_m) begin
            sum <= a_m - b_m;
            z_s <= a_s;
          end else begin
            sum <= b_m - a_m;
            z_s <= b_s;
          end
        end
        state <= add_1;
      end

      add_1:
      begin
        if (sum[`MANTISSA+4]) begin
          z_m <= sum[`MANTISSA+4:4];
          guard <= sum[3];
          round_bit <= sum[2];
          sticky <= sum[1] | sum[0];
          z_e <= z_e + 1;
        end else begin
          z_m <= sum[`MANTISSA+3:3];
          guard <= sum[2];
          round_bit <= sum[1];
          sticky <= sum[0];
        end
        state <= normalise_1;
      end

      normalise_1:
      begin
        if (z_m[`MANTISSA] == 0 && $signed(z_e) > `EXP_MIN) begin
          z_e <= z_e - 1;
          z_m <= z_m << 1;
          z_m[0] <= guard;
          guard <= round_bit;
          round_bit <= 0;
        end else begin
          state <= normalise_2;
        end
      end

      normalise_2:
      begin
        if ($signed(z_e) < `EXP_MIN) begin
          z_e <= z_e + 1;
          z_m <= z_m >> 1;
          guard <= z_m[0];
          round_bit <= guard;
          sticky <= sticky | round_bit;
        end else begin
          state <= round;
        end
      end

      round:
      begin
        if (guard && (round_bit | sticky | z_m[0])) begin
          z_m <= z_m + 1;
          if (z_m == `MTS_MAXVAL) begin
            z_e <=z_e + 1;
          end
        end
        state <= pack;
      end

      pack:
      begin
        z[`MTSBITS] <= z_m[`MTSBITS];
        z[`EXPBITS] <= z_e[`EXPONENT-1:0] + `EXP_MAX;
        z[`WIDTH-1] <= z_s;
        if ($signed(z_e) == `EXP_MIN && z_m[`ELB] == 0) begin
          z[`EXPBITS] <= 0;
        end
        if ($signed(z_e) == `EXP_MIN && z_m[`MANTISSA:0] == 24'h0) begin
          z[`WIDTH-1] <= 1'b0; // FIX SIGN BUG: -a + a = +0.
        end
        //if overflow occurs, return inf
        if ($signed(z_e) > `EXP_MAX) begin
          z[`MTSBITS] <= 0;
          z[`EXPBITS] <= `EXP_MAXVAL;
          z[`WIDTH-1] <= z_s;
        end
        state <= put_z;
      end

      put_z:
      begin
        s_output_z_stb <= 1;
        s_output_z <= z;
        if (s_output_z_stb && output_z_ack) begin
          s_output_z_stb <= 0;
          state <= get_a;
        end
      end

    endcase

    if (rst == 1) begin
      state <= get_a;
      s_input_a_ack <= 0;
      s_input_b_ack <= 0;
      s_output_z_stb <= 0;
    end

  end
  assign input_a_ack = s_input_a_ack;
  assign input_b_ack = s_input_b_ack;
  assign output_z_stb = s_output_z_stb;
  assign output_z = s_output_z;

endmodule

