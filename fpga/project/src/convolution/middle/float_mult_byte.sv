module float_mult_byte (
  input  logic [31:0] float_in,
  input  logic [ 7:0] uint8_in,
  output logic [ 7:0] uint8_out
);

  wire        sign = float_in[31];
  wire [ 7:0] exponent = float_in[30:23];
  wire [22:0] mantissa = float_in[22:0];

  logic [31:0] product;
  logic [31:0] scaled_product;
  logic [ 4:0] right_shift;

  always_comb begin
    product        = '0;
    scaled_product = '0;
    right_shift    = '0;

    if (sign || uint8_in == 0) begin
      uint8_out = 8'd0;
    end else if (exponent == 8'd255) begin
      uint8_out = (mantissa == 0) ? 8'd255 : 8'd0;
    end else if (exponent >= 8'd135) begin
      uint8_out = 8'd255;
    end else if (exponent < 8'd119) begin
      uint8_out = 8'd0;
    end else begin
      product        = {1'b1, mantissa} * uint8_in;
      right_shift    = 5'(8'd150 - exponent);
      scaled_product = product >> right_shift;
      uint8_out      = (scaled_product > 32'd255) ? 8'd255 : 8'(scaled_product);
    end
  end

endmodule
