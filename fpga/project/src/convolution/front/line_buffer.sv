module line_buffer #(
    parameter integer IMAGE_WIDTH = 640
) (
    input logic clk,
    input logic rst_n,

    input logic [$clog2(IMAGE_WIDTH)-1:0] addr,
    input logic [7:0] rx_data,
    output logic [7:0] tx_data,

    input  logic write_en,
    output logic line_valid
);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      line_valid <= 1'b0;
    end else if (write_en && addr == IMAGE_WIDTH - 1) begin
      line_valid <= 1'b1;  // always valid, and `write_en' controls the lines
    end
  end

  Gowin_SP sp (
      .dout (tx_data),
      .clk  (clk),
      .oce  (1'b1),
      .ce   (1'b1),
      .reset(~rst_n),
      .wre  (write_en),
      .ad   (addr),
      .din  (rx_data)
  );

endmodule
