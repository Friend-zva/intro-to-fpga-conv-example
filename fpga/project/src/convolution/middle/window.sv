module window #(
    parameter integer WINDOW_SIZE = 3
) (
    input logic clk,
    input logic rst_n,
    input logic clear,

    input  logic       s_valid,
    input  logic [7:0] s_data,
    output logic       s_ready,

    input  logic       m_ready,
    output logic       m_valid,
    output logic [7:0] m_data [WINDOW_SIZE]
);

  int cnt;

  assign s_ready = !m_valid || m_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cnt <= 0;
      m_valid <= 1'b0;
      for (int i = 0; i < WINDOW_SIZE; i++) begin
        m_data[i] <= '0;
      end
    end else begin
      if (clear) begin
        cnt <= '0;
        m_valid <= 1'b1;
      end

      if (s_valid && s_ready) begin
        for (int i = 0; i < WINDOW_SIZE - 1; i++) begin
          m_data[i] <= m_data[i+1];
        end
        m_data[WINDOW_SIZE-1] <= s_data;

        if (cnt < WINDOW_SIZE) begin
          cnt <= cnt + 1;
        end

        if (cnt >= WINDOW_SIZE - 1) begin
          m_valid <= 1'b1;
        end
      end else if (m_ready) begin
        m_valid <= 1'b0;
      end
    end
  end

endmodule
