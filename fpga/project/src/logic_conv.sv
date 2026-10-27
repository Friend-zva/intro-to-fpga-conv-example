module logic_conv #(
  parameter int AXI_DATA_WIDTH = 256,
  parameter int AXI_ADDR_WIDTH = 29,
  parameter int AXI_LEN_WIDTH  = 20,
  parameter int AXI_STRB_WIDTH = 32,
  parameter int KERNEL_SIZE    = 3,
  parameter int IMAGE_WIDTH    = 640,
  parameter int IMAGE_HEIGHT   = 480
) (
  input logic clk,
  input logic rst_n,

  // Config
  input logic [AXI_ADDR_WIDTH-1:0] cfg_read_addr,
  input logic [AXI_ADDR_WIDTH-1:0] cfg_write_addr,
  input logic [ AXI_LEN_WIDTH-1:0] cfg_len,

  // AXI DMA Descriptors
  taxi_dma_desc_if.req_src rd_desc_req,
  taxi_dma_desc_if.req_src wr_desc_req,
  taxi_dma_desc_if.sts_snk wr_desc_sts,

  // AXI-Stream Data
  taxi_axis_if.snk s_axis_rx,
  taxi_axis_if.src m_axis_tx,

  // Control
  input  logic run,
  output logic done
);

  if (IMAGE_WIDTH < 1 || IMAGE_WIDTH > 640) begin : fatal_image_width
    $fatal(0, "Error: IMAGE_WIDTH must be between 1 and depth SP (instance %m)");
  end
  if (KERNEL_SIZE < 1 || KERNEL_SIZE > 3) begin : fatal_kernel_size
    $fatal(
      0, "Error: KERNEL_SIZE must be between 1 and $sqrt(depth ROM) (instance %m)"
    );
  end

  assign rd_desc_req.req_tag = '0;
  assign wr_desc_req.req_tag = '0;

  localparam int M = KERNEL_SIZE;
  localparam int LINE_PTR = $clog2(M + 1);
  localparam int RD_LATENCY = 2;  // `pipeline` read mode

  logic       rtg_ready;
  logic       rtg_valid;
  logic       rtg_last;
  logic [7:0] rtg_data;

  logic ppb_done_ready;

  rgb_to_grayscale_stream #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_LEN_WIDTH (AXI_LEN_WIDTH)
  ) u_rgb_to_grayscale_stream (
    .clk          (clk),
    .rst_n        (rst_n),
    .cfg_read_addr(cfg_read_addr),
    .cfg_len      (cfg_len),
    .rd_desc_req  (rd_desc_req),
    .s_axis_rx    (s_axis_rx),
    .m_ready      (rtg_ready),
    .m_valid      (rtg_valid),
    .m_last       (rtg_last),
    .m_data       (rtg_data),
    .run          (run)
  );

  logic       demux_ready;
  logic       demux_valid;
  logic       demux_last;
  logic [7:0] demux_data;

  logic [                    M:0] write_en;
  logic [           LINE_PTR-1:0] write_sel;
  logic [$clog2(IMAGE_WIDTH)-1:0] col_addr;

  demux #(
    .M          (M),
    .IMAGE_WIDTH(IMAGE_WIDTH),
    .RD_LATENCY (RD_LATENCY)
  ) u_demux_1_to_m1 (
    .clk      (clk),
    .rst_n    (rst_n),
    .s_valid  (rtg_valid),
    .s_last   (rtg_last),
    .s_data   (rtg_data),
    .s_ready  (rtg_ready),
    .m_ready  (demux_ready),
    .m_valid  (demux_valid),
    .m_last   (demux_last),
    .m_data   (demux_data),
    .write_en (write_en),
    .write_sel(write_sel),
    .addr     (col_addr)
  );

  logic [M:0] line_valid;
  logic [7:0] lb_data    [M+1];

  for (genvar i = 0; i < M + 1; i++) begin : gen_buffers
    line_buffer #(
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .RD_LATENCY (RD_LATENCY)
    ) u_line_buffer (
      .clk       (clk),
      .rst_n     (rst_n),
      .addr      (col_addr),
      .rx_data   (demux_data),
      .tx_data   (lb_data[i]),
      .write_en  (write_en[i]),
      .line_valid(line_valid[i])
    );
  end

  logic       switch_ready;
  logic       switch_valid;
  logic       switch_last;
  logic [7:0] switch_data  [M];

  switch #(
    .M         (M),
    .RD_LATENCY(RD_LATENCY)
  ) u_switch_m1_to_m (
    .clk       (clk),
    .rst_n     (rst_n),
    .write_sel (write_sel),
    .line_valid(line_valid),
    .s_valid   (demux_valid),
    .s_last    (demux_last),
    .s_data    (lb_data),
    .s_ready   (demux_ready),
    .m_ready   (switch_ready),
    .m_valid   (switch_valid),
    .m_last    (switch_last),
    .m_data    (switch_data)
  );

  logic [M-1:0] ker_ready;
  logic [M-1:0] ker_valid;
  logic [ 31:0] ker_data;

  kernel_loader #(
    .KERNEL_SIZE(KERNEL_SIZE),
    .RD_LATENCY (RD_LATENCY)
  ) u_kernel_loader (
    .clk      (clk),
    .rst_n    (rst_n),
    .row_ready(ker_ready),
    .row_valid(ker_valid),
    .data     (ker_data)
  );

  logic [M-1:0] conv_s_ready;
  logic         conv_ready;
  logic [M-1:0] conv_valid;
  logic [  7:0] conv_data    [M];

  for (genvar i = 0; i < M; i++) begin : gen_conv1ds
    conv1d #(
      .KERNEL_SIZE(KERNEL_SIZE)
    ) u_conv1d (
      .clk      (clk),
      .rst_n    (rst_n),
      .ker_valid(ker_valid[i]),
      .ker_data (ker_data),
      .ker_ready(ker_ready[i]),
      .s_valid  (switch_valid),
      .s_last   (switch_last),
      .s_data   (switch_data[i]),
      .s_ready  (conv_s_ready[i]),
      .m_ready  (conv_ready),
      .m_valid  (conv_valid[i]),
      .m_data   (conv_data[i])
    );
  end

  assign switch_ready = &conv_s_ready;

  logic       add_ready;
  logic       add_valid;
  logic [7:0] add_data;

  adder #(
    .KERNEL_SIZE(KERNEL_SIZE)
  ) u_adder (
    .clk    (clk),
    .rst_n  (rst_n),
    .s_valid(&conv_valid),
    .s_data (conv_data),
    .s_ready(conv_ready),
    .m_ready(add_ready),
    .m_valid(add_valid),
    .m_data (add_data)
  );

  logic       ppb_valid;
  logic [7:0] ppb_data;

  logic ppb_done_sel;
  logic ppb_done;

  logic                           ddr_rd_req;
  logic                           ddr_rd_sel;
  logic [$clog2(IMAGE_WIDTH)-1:0] ddr_rd_addr;

  ping_pong_buffer #(
    .IMAGE_WIDTH(IMAGE_WIDTH - 2 * (KERNEL_SIZE / 2)),
    .RD_LATENCY (RD_LATENCY)
  ) u_ping_pong_buffer (
    .clk       (clk),
    .rst_n     (rst_n),
    .s_valid   (add_valid),
    .s_data    (add_data),
    .s_ready   (add_ready),
    .m_valid   (ppb_valid),
    .m_data    (ppb_data),
    .rd_req    (ddr_rd_req),
    .rd_sel    (ddr_rd_sel),
    .rd_addr   (ddr_rd_addr),
    .done      (ppb_done),
    .done_ready(ppb_done_ready),
    .done_sel  (ppb_done_sel)
  );

  grayscale_stream #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_LEN_WIDTH (AXI_LEN_WIDTH),
    .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
    .KERNEL_SIZE   (KERNEL_SIZE),
    .IMAGE_WIDTH   (IMAGE_WIDTH),
    .IMAGE_HEIGHT  (IMAGE_HEIGHT)
  ) u_grayscale_stream (
    .clk           (clk),
    .rst_n         (rst_n),
    .cfg_write_addr(cfg_write_addr),
    .s_valid       (ppb_valid),
    .s_data        (ppb_data),
    .wr_desc_req   (wr_desc_req),
    .m_axis_tx     (m_axis_tx),
    .ppb_done      (ppb_done),
    .ppb_done_ready(ppb_done_ready),
    .ppb_done_sel  (ppb_done_sel),
    .rd_req        (ddr_rd_req),
    .rd_sel        (ddr_rd_sel),
    .rd_addr       (ddr_rd_addr)
  );

  logic [$clog2(IMAGE_HEIGHT)-1:0] wr_status_cnt;
  logic                            run_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) run_reg <= 1'b0;
    else run_reg <= run;
  end

  logic run_pulse;
  assign run_pulse = run && !run_reg;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_status_cnt <= '0;
      done          <= 1'b0;
    end else if (run_pulse) begin
      wr_status_cnt <= '0;
      done          <= 1'b0;
    end else if (wr_desc_sts.sts_valid && !done) begin
      if (wr_status_cnt == (IMAGE_HEIGHT - 2 * (KERNEL_SIZE / 2))) begin
        done <= 1'b1;
      end else begin
        wr_status_cnt <= wr_status_cnt + 1;
      end
    end
  end

endmodule
