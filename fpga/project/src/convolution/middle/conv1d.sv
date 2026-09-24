module conv1d #(
    parameter integer KERNEL_SIZE = 3
) (
    input logic clk,
    input logic rst_n,
    input logic win_clear,

    input  logic        ker_valid,
    input  logic [31:0] ker_data,
    output logic        ker_ready,

    input  logic       s_valid,
    input  logic [7:0] s_data,
    output logic       s_ready,

    input  logic       m_ready,
    output logic       m_valid,
    output logic [7:0] m_data
);

  int          weights_cnt;
  logic [31:0] ker_vector  [KERNEL_SIZE];

  assign ker_ready = (weights_cnt < KERNEL_SIZE);
  wire ker_done = (weights_cnt == KERNEL_SIZE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      weights_cnt <= 0;
      for (int i = 0; i < KERNEL_SIZE; i++) begin
        ker_vector[i] <= '0;
      end
    end else if (ker_ready && ker_valid) begin
      ker_vector[weights_cnt] <= ker_data;
      weights_cnt             <= weights_cnt + 1;
    end
  end

  wire        win_ready = m_ready && ker_done;
  logic       win_valid;
  logic [7:0] win_data                        [KERNEL_SIZE];

  window #(
      .WINDOW_SIZE(KERNEL_SIZE)
  ) u_window (
      .clk(clk),
      .rst_n(rst_n),
      .clear(win_clear),
      .s_data(s_data),
      .s_valid(s_valid && ker_done),
      .s_ready(s_ready),
      .m_ready(win_ready),
      .m_valid(win_valid),
      .m_data(win_data)
  );

  scalar_product #(
      .VECTOR_SIZE(KERNEL_SIZE)
  ) u_scalar_product (
      .vector(ker_vector),
      .uint8_in(win_data),
      .uint8_out(m_data)
  );

  assign m_valid = win_valid && ker_done;

endmodule
