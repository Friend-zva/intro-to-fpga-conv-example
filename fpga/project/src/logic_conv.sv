module logic_conv #(
    parameter integer AXI_DATA_WIDTH = 256,
    parameter integer AXI_ADDR_WIDTH = 29,
    parameter integer AXI_LEN_WIDTH = 20,
    parameter integer AXI_STRB_WIDTH = 32,
    parameter integer KERNEL_SIZE = 3,
    parameter integer IMAGE_WIDTH = 640,
    parameter integer IMAGE_HEIGHT = 480
) (
    input clk,
    input rst_n,

    // Config
    input [AXI_ADDR_WIDTH-1:0] cfg_read_addr,
    input [AXI_ADDR_WIDTH-1:0] cfg_write_addr,
    input [ AXI_LEN_WIDTH-1:0] cfg_len,

    // AXI DMA Descriptors
    taxi_dma_desc_if.req_src rd_desc_req,
    taxi_dma_desc_if.req_src wr_desc_req,
    taxi_dma_desc_if.sts_snk wr_desc_sts,

    // AXI-Stream Data
    taxi_axis_if.snk s_axis_rx,
    taxi_axis_if.src m_axis_tx,

    // Control
    input      run,
    output reg done
);

  assign rd_desc_req.req_tag = '0;
  assign wr_desc_req.req_tag = '0;

  localparam integer M = KERNEL_SIZE;
  localparam integer LINE_PTR = $clog2(M + 1);

  logic rtg_valid;
  logic rtg_ready;
  logic [7:0] rtg_data;

  rgb_to_grayscale_stream #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_LEN_WIDTH (AXI_LEN_WIDTH)
  ) u_rgb_to_grayscale_stream (
      .clk(clk),
      .rst_n(rst_n),
      .cfg_read_addr(cfg_read_addr),
      .cfg_len(cfg_len),
      .rd_desc_req(rd_desc_req),
      .s_axis_rx(s_axis_rx),
      .m_valid(rtg_valid),
      .m_ready(rtg_ready),
      .m_data(rtg_data),
      .run(run)
  );

  logic                           demux_ready;
  logic [                    7:0] demux_data;
  logic [                    M:0] write_en;
  logic [           LINE_PTR-1:0] write_sel;
  logic [$clog2(IMAGE_WIDTH)-1:0] col_addr;

  demux_1_to_m1 #(
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .M(M)
  ) u_demux_1_to_m1 (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(rtg_valid),
      .s_ready(rtg_ready),
      .s_data(rtg_data),
      .m_ready(demux_ready),
      .m_data(demux_data),
      .write_en(write_en),
      .write_sel(write_sel),
      .addr(col_addr)
  );

  logic [7:0] lb_data    [M+1];
  logic [M:0] line_valid;

  genvar i;
  generate
    for (i = 0; i < M + 1; i++) begin : gen_buffers
      line_buffer #(
          .IMAGE_WIDTH(IMAGE_WIDTH)
      ) u_line_buffer (
          .clk(clk),
          .rst_n(rst_n),
          .addr(col_addr),
          .rx_data(demux_data),
          .tx_data(lb_data[i]),
          .write_en(write_en[i]),
          .line_valid(line_valid[i])
      );
    end
  endgenerate

  logic mux_valid;
  logic [7:0] mux_data[M];

  mux_m1_to_m #(
      .M(M)
  ) u_mux_m1_to_m (
      .write_sel(write_sel),
      .rx_data  (lb_data),
      .tx_data  (mux_data)
  );

  always_comb begin
    mux_valid = 1'b1;
    for (int j = 0; j < M + 1; j++) begin
      if (j != int'(write_sel)) begin
        mux_valid &= line_valid[j];
      end
    end
  end

  logic [M-1:0] w_valid;
  logic [M-1:0] w_ready;
  logic [ 31:0] w_data;

  weight_loader #(
      .KERNEL_SIZE(KERNEL_SIZE)
  ) u_weight_loader (
      .clk(clk),
      .rst_n(rst_n),
      .row_valid(w_valid),
      .row_ready(w_ready),
      .data(w_data)
  );

  logic [M-1:0] conv_s_ready;
  logic         conv_ready;
  logic [M-1:0] conv_valid;
  logic         conv_valid_full;
  logic [  7:0] conv_data       [M];

  generate
    for (i = 0; i < M; i++) begin : gen_conv1d
      conv1d #(
          .KERNEL_SIZE(KERNEL_SIZE)
      ) u_conv1d (
          .clk(clk),
          .rst_n(rst_n),
          .w_valid(w_valid[i]),
          .w_ready(w_ready[i]),
          .w_data(w_data),
          .s_valid(mux_valid),
          .s_ready(conv_s_ready[i]),
          .s_data(mux_data[i]),
          .m_valid(conv_valid[i]),
          .m_ready(conv_ready),
          .m_data(conv_data[i])
      );
    end
  endgenerate

  assign demux_ready = &conv_s_ready;
  assign conv_valid_full = &conv_valid;

  logic       add_ready;
  logic       add_valid;
  logic [7:0] add_data;

  adder #(
      .KERNEL_SIZE(KERNEL_SIZE)
  ) u_adder (
      .clk    (clk),
      .rst_n  (rst_n),
      .s_valid(conv_valid_full),
      .s_ready(conv_ready),
      .s_data (conv_data),
      .m_ready(add_ready),
      .m_valid(add_valid),
      .m_data (add_data)
  );

  logic [$clog2(IMAGE_WIDTH)-1:0] ddr_rd_addr;
  logic                           ddr_rd_buf_sel;

  logic                           buf_valid;
  logic [                    7:0] buf_data;

  logic buf_done, buf_done_sel;
  logic buf_done_ready;

  ping_pong_buffer #(
      .IMAGE_WIDTH(IMAGE_WIDTH - 2 * (KERNEL_SIZE / 2))
  ) u_ping_pong_buffer (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(add_valid),
      .s_ready(add_ready),
      .s_data(add_data),
      .rd_addr(ddr_rd_addr),
      .rd_buf_sel(ddr_rd_buf_sel),
      .m_valid(buf_valid),
      .m_data(buf_data),
      .done(buf_done),
      .done_ready(buf_done_ready),
      .done_sel(buf_done_sel)
  );

  grayscale_to_ddr3_stream #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
      .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
      .KERNEL_SIZE(KERNEL_SIZE),
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .IMAGE_HEIGHT(IMAGE_HEIGHT)
  ) u_grayscale_to_ddr3 (
      .clk(clk),
      .rst_n(rst_n),
      .cfg_write_addr(cfg_write_addr),
      .wr_desc_req(wr_desc_req),
      .m_axis_tx(m_axis_tx),
      .buf_done(buf_done),
      .buf_done_ready(buf_done_ready),
      .buf_done_sel(buf_done_sel),
      .rd_addr(ddr_rd_addr),
      .rd_buf_sel(ddr_rd_buf_sel),
      .s_data(buf_data)
  );

  logic [$clog2(IMAGE_HEIGHT)-1:0] wr_status_cnt;
  logic run_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) run_reg <= 1'b0;
    else run_reg <= run;
  end

  wire run_pulse = run && !run_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_status_cnt <= '0;
      done <= 1'b0;
    end else if (run_pulse) begin
      wr_status_cnt <= '0;
      done <= 1'b0;
    end else if (wr_desc_sts.sts_valid && !done) begin
      if (wr_status_cnt == (IMAGE_HEIGHT - 2 * (KERNEL_SIZE / 2))) begin
        done <= 1'b1;
      end else begin
        wr_status_cnt <= wr_status_cnt + 1;
      end
    end
  end

endmodule
