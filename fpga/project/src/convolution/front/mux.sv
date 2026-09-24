module mux_m1_to_m #(
    parameter integer M = 3,
    parameter integer RD_LATENCY = 2
) (
    input logic clk,
    input logic rst_n,

    input logic [$clog2(M+1)-1:0] write_sel,
    input logic [M:0] line_valid,

    input logic s_valid,
    input logic [7:0] s_data[M+1],
    output logic s_ready,

    input logic m_ready,
    output logic m_valid,
    output logic [7:0] m_data[M]
);
  localparam integer N = M + 1;

  assign s_ready = m_ready;

  always_comb begin
    for (int i = 0; i < M; i++) begin
      m_data[i] = s_data[(write_sel+1+i)%N];
    end
  end

  logic [RD_LATENCY-1:0] valid_pipe;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      valid_pipe <= '0;
    end else begin
      valid_pipe <= {valid_pipe[RD_LATENCY-2:0], s_valid};
    end
  end

  always_comb begin
    m_valid = valid_pipe[RD_LATENCY-1];
    for (int j = 0; j < M + 1; j++) begin
      if (j != int'(write_sel)) begin
        m_valid &= line_valid[j];
      end
    end
  end

endmodule
