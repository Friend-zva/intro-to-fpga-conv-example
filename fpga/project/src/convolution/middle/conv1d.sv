module conv1d #(
    parameter integer KERNEL_SIZE = 3
) (
    input logic clk,
    input logic rst_n,

    input  logic        w_valid,
    output logic        w_ready,
    input  logic [31:0] w_data,

    input  logic       s_valid,
    output logic       s_ready,
    input  logic [7:0] s_data,

    output logic       m_valid,
    input  logic       m_ready,
    output logic [7:0] m_data
);

  int          w_cnt;
  logic [31:0] weights [KERNEL_SIZE];
  logic [ 7:0] win_data[KERNEL_SIZE];

  assign w_ready = (w_cnt < KERNEL_SIZE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      w_cnt <= 0;
      for (int i = 0; i < KERNEL_SIZE; i++) begin
        weights[i] <= '0;
      end
    end else if (w_ready && w_valid) begin
      weights[w_cnt] <= w_data;
      w_cnt          <= w_cnt + 1;
    end
  end

  wire  w_done = (w_cnt == KERNEL_SIZE);

  logic win_valid;
  wire  win_ready = m_ready && w_done;

  window #(
      .WIN_SIZE(KERNEL_SIZE)
  ) u_window (
      .clk(clk),
      .rst_n(rst_n),
      .clear(w_done),
      .s_data(s_data),
      .s_valid(s_valid && w_done),
      .s_ready(s_ready),
      .m_ready(win_ready),
      .m_valid(win_valid),
      .m_data(win_data)
  );

  scalar_product #(
      .VECTOR_CNT(KERNEL_SIZE)
  ) u_scalar_product (
      .float_in (weights),
      .uint8_in (win_data),
      .uint8_out(m_data)
  );

  assign m_valid = win_valid && w_done;

endmodule
