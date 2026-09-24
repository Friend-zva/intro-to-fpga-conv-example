module ping_pong_buffer #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer RD_LATENCY  = 2
) (
    input logic clk,
    input logic rst_n,

    input  logic       s_valid,
    input  logic [7:0] s_data,
    output logic       s_ready,

    input logic                           rd_req,
    input logic                           rd_buf_sel,
    input logic [$clog2(IMAGE_WIDTH)-1:0] rd_addr,

    output logic       m_valid,
    output logic [7:0] m_data,

    input  logic done_ready,
    output logic done,
    output logic done_sel
);

  logic [$clog2(IMAGE_WIDTH)-1:0] wr_addr;
  logic wr_bank;
  logic [1:0] done_all;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_addr  <= '0;
      wr_bank  <= 1'b0;
      done_all <= 1'b0;
      done_sel <= 1'b0;
    end else begin
      if (done && done_ready) begin
        done_all[wr_bank] <= 1'b0;
        wr_bank           <= ~wr_bank;
        wr_addr           <= '0;
      end else if (s_valid && s_ready) begin
        if (wr_addr == IMAGE_WIDTH - 1) begin
          done_all[wr_bank] <= 1'b1;
          done_sel          <= wr_bank;
        end else begin
          wr_addr <= wr_addr + 1'b1;
        end
      end
    end
  end

  assign done    = done_all[wr_bank];
  assign s_ready = !(&done_all);

  logic [7:0] bank_data[2];

  genvar b;
  generate
    for (b = 0; b < 2; b++) begin : gen_bank
      wire wr_bank_sel = (wr_bank == b[0]);
      wire wr_bank_en = s_valid && s_ready && wr_bank_sel;
      wire [$clog2(IMAGE_WIDTH)-1:0] bank_addr = wr_bank_en ? wr_addr : rd_addr;

      Gowin_SP u_bank (
          .dout (bank_data[b]),
          .clk  (clk),
          .oce  (1'b1),
          .ce   (1'b1),
          .reset(~rst_n),
          .wre  (wr_bank_en),
          .ad   (bank_addr),
          .din  (s_data)
      );
    end
  endgenerate

  logic valid_pipe[RD_LATENCY];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < RD_LATENCY; i++) begin
        valid_pipe[i] <= 1'b0;
      end
    end else begin
      valid_pipe[0] <= rd_req;
      for (int i = 1; i < RD_LATENCY; i++) begin
        valid_pipe[i] <= valid_pipe[i-1];
      end
    end
  end

  assign m_valid = valid_pipe[RD_LATENCY-1];
  assign m_data  = bank_data[rd_buf_sel];

endmodule
