module scalar_product #(
    parameter integer VECTOR_SIZE = 4
) (
    input logic [31:0] vector[VECTOR_SIZE],
    input logic [7:0] uint8_in[VECTOR_SIZE],
    output logic [7:0] uint8_out
);

  logic [7:0] temp[VECTOR_SIZE];

  genvar i;
  generate
    for (i = 0; i < VECTOR_SIZE; i++) begin : gen_mult
      float_mult_byte float_mult (
          .float_in (vector[i]),
          .uint8_in (uint8_in[i]),
          .uint8_out(temp[i])
      );
    end
  endgenerate

  int unsigned sum;
  always_comb begin
    sum = '0;
    for (int j = 0; j < VECTOR_SIZE; j++) begin
      sum = sum + temp[j];
    end

    uint8_out = (sum > 255) ? 8'd255 : sum[7:0];
  end

endmodule
