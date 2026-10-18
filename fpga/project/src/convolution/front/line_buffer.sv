module line_buffer #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer RD_LATENCY  = 2
) (
    input logic clk,
    input logic rst_n,

    input logic [$clog2(IMAGE_WIDTH)-1:0] addr,

    input  logic [7:0] rx_data,
    output logic [7:0] tx_data,

    input  logic write_en,
    output logic line_valid
);

  if (RD_LATENCY < 1) begin : fatal_latency
    $fatal(0, "Error: RD_LATENCY must be more than 0");
  end

  logic [RD_LATENCY-1:0] valid_pipe;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      line_valid <= 1'b0;
      valid_pipe <= '0;
    end else begin
      valid_pipe[0] <= (write_en && addr == IMAGE_WIDTH - 1);
      for (int i = 1; i < RD_LATENCY; i++) begin
        valid_pipe[i] <= valid_pipe[i-1];
      end

      if (valid_pipe[RD_LATENCY-1]) begin
        line_valid <= 1'b1;  // always valid once set to 1, lines driven by `write_en`
      end
    end
  end

  Gowin_SP u_line (
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
