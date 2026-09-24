module adder #(
    parameter integer KERNEL_SIZE = 3
) (
    input logic clk,
    input logic rst_n,

    input logic s_valid,
    input logic [7:0] s_data[KERNEL_SIZE],
    output logic s_ready,

    input logic m_ready,
    output logic m_valid,
    output logic [7:0] m_data
);

  int unsigned sum;
  always_comb begin
    sum = 0;
    for (int i = 0; i < KERNEL_SIZE; i++) begin
      sum = sum + s_data[i];
    end
  end

  assign s_ready = !m_valid || m_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_data  <= '0;
      m_valid <= 1'b0;
    end else begin
      if (s_valid && s_ready) begin
        m_data  <= (sum > 255) ? 8'd255 : sum[7:0];
        m_valid <= 1'b1;
      end else if (m_ready) begin
        m_valid <= 1'b0;
      end
    end
  end

endmodule
