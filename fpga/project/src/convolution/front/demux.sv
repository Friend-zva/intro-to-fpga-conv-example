module demux_1_to_m1 #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer M           = 3
) (
    input logic clk,
    input logic rst_n,

    input  logic       s_valid,
    output logic       s_ready,
    input  logic [7:0] s_data,

    output logic       m_valid,
    input  logic       m_ready,
    output logic [7:0] m_data,

    output logic [            M:0] write_en,
    output logic [$clog2(M+1)-1:0] write_sel,

    output logic [$clog2(IMAGE_WIDTH)-1:0] addr
);
  localparam integer SEL_W = $clog2(M + 1);

  assign s_ready = m_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr <= '0;
      write_sel <= '0;
    end else if (s_valid && s_ready) begin
      if (addr == IMAGE_WIDTH - 1) begin
        addr <= '0;
        write_sel <= (write_sel == M[SEL_W-1:0]) ? '0 : write_sel + 1;
      end else begin
        addr <= addr + 1;
      end
    end
  end

  assign m_valid = s_valid & s_ready;
  assign m_data  = s_data;

  always_comb begin
    write_en = '0;
    if (s_valid && s_ready) begin
      write_en[write_sel] = 1'b1;
    end
  end

endmodule
