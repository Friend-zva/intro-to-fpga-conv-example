module scalar_product #(
    parameter integer VECTOR_CNT = 4
) (
    input logic [31:0] float_in[VECTOR_CNT],
    input logic [ 7:0] uint8_in[VECTOR_CNT],

    output logic [7:0] uint8_out
);

  logic [7:0] temp[VECTOR_CNT];

  genvar i;
  generate
    for (i = 0; i < VECTOR_CNT; i++) begin : gen_mult
      float_mult_byte float_mult (
          .float_in (float_in[i]),
          .uint8_in (uint8_in[i]),
          .uint8_out(temp[i])
      );
    end
  endgenerate

  int unsigned sum;
  always_comb begin
    sum = '0;
    for (int j = 0; j < VECTOR_CNT; j++) begin
      sum = sum + temp[j];
    end

    uint8_out = (sum > 255) ? 8'd255 : sum[7:0];
  end

endmodule
