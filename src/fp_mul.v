//IEEE Floating Point Multiplier (Single Precision)
//Copyright (C) Jonathan P Dawson 2013
//2013-12-12

// derived defines
`define BIAS ((1 << (`EXPONENT-1)) - 1)
`define NEG_BIAS -`BIAS
`define MAXVAL ((1 << `EXPONENT) - 1)
`define BIAS_PO `BIAS+1
`define NEG_BIAS_PO `NEG_BIAS+1
`define SB `WIDTH-1
`define EHB `WIDTH-2
`define EXPBITS `EHB:`MANTISSA
`define EXP_PO `EXPONENT+1
`define EXP_MO `EXPONENT-1
`define MHB `MANTISSA-1
`define MTS_PO `MANTISSA+1
`define MTSBITS `MHB:0
`define PROD_NUM ((`MANTISSA*2) + 1)
`define PRODBITS `PROD_NUM:`MTS_PO

module fp_mul(
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

  localparam LEN = `MTS_PO;

  input     clk;
  input     rst;

  input     [`SB:0] input_a;
  input     input_a_stb;
  output    input_a_ack;

  input     [`SB:0] input_b;
  input     input_b_stb;
  output    input_b_ack;

  output    [`SB:0] output_z;
  output    output_z_stb;
  input     output_z_ack;

  reg       s_output_z_stb;
  reg       [`SB:0] s_output_z;
  reg       s_input_a_ack;
  reg       s_input_b_ack;

  reg       [3:0] state;
  parameter get_a         = 4'd0,
            get_b         = 4'd1,
            unpack        = 4'd2,
            special_cases = 4'd3,
            normalise_a   = 4'd4,
            normalise_b   = 4'd5,
            multiply_0    = 4'd6,
            multiply_1    = 4'd7,
            normalise_1   = 4'd8,
            normalise_2   = 4'd9,
            round         = 4'd10,
            pack          = 4'd11,
            put_z         = 4'd12;

  reg       [`SB:0] a, b, z;
  reg       [`MANTISSA:0] a_m, b_m, z_m;
  reg       [`EXP_PO:0] a_e, b_e, z_e;
  reg       a_s, b_s, z_s;
  reg       guard, round_bit, sticky;
  reg       [`PROD_NUM:0] product;

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
        a_m <= a[`MTSBITS];
        b_m <= b[`MTSBITS];
        a_e <= a[`EXPBITS] - `BIAS;
        b_e <= b[`EXPBITS] - `BIAS;
        a_s <= a[`SB];
        b_s <= b[`SB];
        state <= special_cases;
      end

      special_cases:
      begin
        //if a is NaN or b is NaN return NaN 
        if ((a_e == `BIAS_PO && a_m != 0) || (b_e == `BIAS_PO && b_m != 0)) begin
          z[`SB] <= 1;
          z[`EXPBITS] <= `MAXVAL;
          z[`MHB] <= 1;
          z[`MHB-1:0] <= 0;
          state <= put_z;
        //if a is inf return inf
        end else if (a_e == `BIAS_PO) begin
          z[`SB] <= a_s ^ b_s;
          z[`EXPBITS] <= `MAXVAL;
          z[`MTSBITS] <= 0;
          //if b is zero return NaN
          if (($signed(b_e) == `NEG_BIAS) && (b_m == 0)) begin
            z[`SB] <= 1;
            z[`EXPBITS] <= `MAXVAL;
            z[`MHB] <= 1;
            z[`MHB-1:0] <= 0;
          end
          state <= put_z;
        //if b is inf return inf
        end else if (b_e == `BIAS_PO) begin
          z[`SB] <= a_s ^ b_s;
          z[`EXPBITS] <= `MAXVAL;
          z[`MTSBITS] <= 0;
          //if a is zero return NaN
          if (($signed(a_e) == `NEG_BIAS) && (a_m == 0)) begin
            z[`SB] <= 1;
            z[`EXPBITS] <= `MAXVAL;
            z[`MHB] <= 1;
            z[`MHB-1:0] <= 0;
          end
          state <= put_z;
        //if a is zero return zero
        end else if (($signed(a_e) == `NEG_BIAS) && (a_m == 0)) begin
          z[`SB] <= a_s ^ b_s;
          z[`EXPBITS] <= 0;
          z[`MTSBITS] <= 0;
          state <= put_z;
        //if b is zero return zero
        end else if (($signed(b_e) == `NEG_BIAS) && (b_m == 0)) begin
          z[`SB] <= a_s ^ b_s;
          z[`EXPBITS] <= 0;
          z[`MTSBITS] <= 0;
          state <= put_z;
        end else begin
          //Denormalised Number
          if ($signed(a_e) == `NEG_BIAS) begin
            a_e <= `NEG_BIAS_PO;
          end else begin
            a_m[`MANTISSA] <= 1;
          end
          //Denormalised Number
          if ($signed(b_e) == `NEG_BIAS) begin
            b_e <= `NEG_BIAS_PO;
          end else begin
            b_m[`MANTISSA] <= 1;
          end
          state <= normalise_a;
        end
      end

      normalise_a:
      begin
        if (a_m[`MANTISSA]) begin
          state <= normalise_b;
        end else begin
          a_m <= a_m << 1;
          a_e <= a_e - 1;
        end
      end

      normalise_b:
      begin
        if (b_m[`MANTISSA]) begin
          state <= multiply_0;
        end else begin
          b_m <= b_m << 1;
          b_e <= b_e - 1;
        end
      end

      multiply_0:
      begin
        z_s <= a_s ^ b_s;
        z_e <= a_e + b_e + 1;
        product <= a_m * b_m;
        state <= multiply_1;
      end

      multiply_1:
      begin
        z_m <= product[`PRODBITS];
        guard <= product[`MANTISSA];
        round_bit <= product[`MHB];
        sticky <= (product[`MHB-1:0] != 0);
        state <= normalise_1;
      end

      normalise_1:
      begin
        if (z_m[`MANTISSA] == 0) begin
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
        if ($signed(z_e) < `NEG_BIAS_PO) begin
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
          if (z_m == {LEN{1'b1}}) begin
            z_e <=z_e + 1;
          end
        end
        state <= pack;
      end

      pack:
      begin
        z[`MTSBITS] <= z_m[`MTSBITS];
        z[`EXPBITS] <= z_e[`EXP_MO:0] + `BIAS;
        z[`SB] <= z_s;
        if ($signed(z_e) == `NEG_BIAS_PO && z_m[`MANTISSA] == 0) begin
          z[`EXPBITS] <= 0;
        end
        //if overflow occurs, return inf
        if ($signed(z_e) > `BIAS) begin
          z[`MTSBITS] <= 0;
          z[`EXPBITS] <= `MAXVAL;
          z[`SB] <= z_s;
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