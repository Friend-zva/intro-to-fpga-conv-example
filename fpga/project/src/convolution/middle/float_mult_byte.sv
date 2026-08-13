module float_mult_byte (
    input logic [31:0] float_in,
    input logic [ 7:0] uint8_in,

    output logic [7:0] uint8_out
);

  logic               sign;
  logic        [ 7:0] exponent;
  logic        [22:0] mantissa;

  logic signed [ 8:0] exp_shift;
  logic        [31:0] mant_x_pixel;
  logic        [31:0] pixel_ext;
  logic        [32:0] fraction_sum;
  logic        [31:0] scaled_mantissa;

  always_comb begin
    sign            = float_in[31];
    exponent        = float_in[30:23];
    mantissa        = float_in[22:0];
    exp_shift       = '0;
    mant_x_pixel    = '0;
    pixel_ext       = '0;
    fraction_sum    = '0;
    scaled_mantissa = '0;

    if (sign && exponent == 8'd255 && mantissa == 0) begin
      uint8_out = 8'd0;
    end else if (!sign && exponent == 8'd255 && mantissa == 0) begin
      uint8_out = (uint8_in > 0) ? 8'd255 : 8'd0;
    end else if (exponent == 8'd255 && mantissa != 0) begin
      uint8_out = 8'd0;
    end else begin
      exp_shift    = signed'({1'b0, exponent}) - 9'sd127;
      mant_x_pixel = mantissa * uint8_in;
      pixel_ext    = {24'd0, uint8_in};

      if (exp_shift >= 23) begin
        scaled_mantissa = (mant_x_pixel << (exp_shift - 23)) + (pixel_ext << exp_shift);
      end else if (exp_shift >= 0) begin
        scaled_mantissa = (mant_x_pixel >> (23 - exp_shift)) + (pixel_ext << exp_shift);
      end else begin
        if ((pixel_ext << (32 + exp_shift)) == 0) begin
          fraction_sum = mant_x_pixel << (32 + exp_shift - 23);
        end else begin
          fraction_sum = (mant_x_pixel << (32 + exp_shift - 23)) + (pixel_ext << (32 + exp_shift));
        end
        scaled_mantissa = (mant_x_pixel >> (23 - exp_shift)) +
                           (pixel_ext >> (-exp_shift)) +
                           fraction_sum[32];
      end

      if (scaled_mantissa > 255) begin
        uint8_out = 8'd255;
      end else if (scaled_mantissa == 0 || sign) begin
        uint8_out = 8'd0;
      end else begin
        uint8_out = scaled_mantissa[7:0];
      end
    end
  end

endmodule
