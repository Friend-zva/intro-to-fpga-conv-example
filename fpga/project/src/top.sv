module top (
    input sys_clk_p,
    input pcie_rst_n,
    input hard_rst_n,

    output [5:0] led,

    output [14:0] ddr_addr,
    output [2:0] ddr_ba,
    output ddr_cs_n,
    output ddr_ras_n,
    output ddr_cas_n,
    output ddr_we_n,
    output ddr_clk,
    output ddr_clk_n,
    output ddr_cke,
    output ddr_odt,
    output ddr_reset_n,
    output [3:0] ddr_dqm,
    inout [31:0] ddr_dq,
    inout [3:0] ddr_dqs,
    inout [3:0] ddr_dqs_n
);

  // ==========
  // Parameters
  // ==========
  // Clocks
  localparam integer PCIE_DLY = 8;
  localparam integer PERST_DLY = 25;
  localparam integer RUN_DLY = 23;
  localparam integer SYS_RST_DLY = 20;
  // AXI
  localparam integer AXI_FIFO_DEPTH = 128;
  localparam integer AXI_DATA_WIDTH = 256;
  localparam integer AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
  localparam integer AXI_ID_WIDTH = 4;
  localparam integer AXI_BURST_LEN = 1;
  localparam integer AXI_ADDR_WIDTH = 30;
  localparam integer AXI_LEN_WIDTH = AXI_ADDR_WIDTH + 1;

  // ===============
  // Clocks & Resets
  // ===============
  // Clocks
  wire sys_clk;
  /* synthesis syn_keep = 1 */
  wire cfg_clk;
  /* synthesis syn_keep = 1 */
  wire memory_clk;
  /* synthesis syn_keep = 1 */
  wire div_clk, tlp_clk, ddr_in_clk;
  wire pll_50m_clk, pll_200m_clk, pll_400m_clk;
  wire pll_lock, pll_stop;

  Gowin_PLL u_pll (
      .clkin(sys_clk_p),
      .init_clk(sys_clk_p),
      .clkout0(pll_50m_clk),
      .clkout1(pll_200m_clk),
      .clkout2(pll_400m_clk),
      .enclk0(1'b1),
      .enclk1(1'b1),
      .enclk2(pll_stop),
      .lock(pll_lock),
      .reset(~hard_rst_n)
  );
  assign sys_clk = pll_200m_clk;
  assign memory_clk = pll_400m_clk;

  CLKDIV #(
      .DIV_MODE("2")
  ) uut_div2 (
      div_clk,
      'b0,
      sys_clk,
      'b1
  );
  assign cfg_clk = div_clk;
  assign tlp_clk = div_clk;
  assign ddr_in_clk = div_clk;

  wire ddr_out_clk, ddr_out_rst;
  wire                 ui_clk = ddr_out_clk;
  wire                 pcie_start;
  wire                 ddr_init;

  // Reset generate
  reg  [         26:0] pcie_st_cnt = 0;
  reg  [         26:0] run_cnt = 0;
  reg  [         26:0] perst_cnt = 0;
  reg  [SYS_RST_DLY:0] sys_rst_cnt = 0;

  wire                 rst_n = hard_rst_n & pcie_rst_n;
  wire                 ui_rst = ddr_out_rst | !rst_n | !pcie_start;

  // PCIe start delay
  always @(posedge cfg_clk or negedge rst_n)
    if (!rst_n) sys_rst_cnt <= 0;
    else if (!sys_rst_cnt[SYS_RST_DLY]) sys_rst_cnt <= sys_rst_cnt + 1'd1;

  wire sys_rst_n = sys_rst_cnt[SYS_RST_DLY];

  always @(posedge cfg_clk or negedge sys_rst_n)
    if (!sys_rst_n) perst_cnt <= 0;
    else if (!perst_cnt[PERST_DLY]) perst_cnt <= perst_cnt + 1'd1;

  always @(posedge cfg_clk or negedge sys_rst_n)
    if (!sys_rst_n) pcie_st_cnt <= 0;
    else if (!pcie_start) pcie_st_cnt <= pcie_st_cnt + 1'd1;

  assign pcie_start = pcie_st_cnt[PCIE_DLY] ? 1'b1 : 1'b0;

  // Control led blink
  always @(posedge cfg_clk or negedge rst_n)
    if (!rst_n) run_cnt <= 0;
    else run_cnt <= run_cnt + 1'd1;

  wire pcie_linkup;
  reg  pcie_linkup_r = 0;
  /* synthesis syn_keep = 1 */

  always @(posedge cfg_clk) pcie_linkup_r <= pcie_linkup;

  // ============
  // Interconnect
  // ============
  // Slave Interfaces (PCIe DMA [0], Logic DMA [1])
  taxi_axi_if #(
      .DATA_W(AXI_DATA_WIDTH),
      .ADDR_W(AXI_ADDR_WIDTH),
      .STRB_W(AXI_STRB_WIDTH),
      .ID_W  (AXI_ID_WIDTH)
  ) axi_ic_s_wr[2] ();
  taxi_axi_if #(
      .DATA_W(AXI_DATA_WIDTH),
      .ADDR_W(AXI_ADDR_WIDTH),
      .STRB_W(AXI_STRB_WIDTH),
      .ID_W  (AXI_ID_WIDTH)
  ) axi_ic_s_rd[2] ();
  // Master Interfaces (DDR3)
  taxi_axi_if #(
      .DATA_W(AXI_DATA_WIDTH),
      .ADDR_W(AXI_ADDR_WIDTH),
      .STRB_W(AXI_STRB_WIDTH),
      .ID_W  (AXI_ID_WIDTH)
  ) axi_ic_m_wr[1] ();
  taxi_axi_if #(
      .DATA_W(AXI_DATA_WIDTH),
      .ADDR_W(AXI_ADDR_WIDTH),
      .STRB_W(AXI_STRB_WIDTH),
      .ID_W  (AXI_ID_WIDTH)
  ) axi_ic_m_rd[1] ();

  taxi_axi_interconnect #(
      .S_COUNT(2),
      .M_COUNT(1),
      .ADDR_W(AXI_ADDR_WIDTH),
      .M_REGIONS(1),
      .M_ADDR_W(AXI_ADDR_WIDTH)
  ) u_axi_interconnect (
      .clk(ui_clk),
      .rst(ui_rst),
      .s_axi_wr(axi_ic_s_wr),
      .s_axi_rd(axi_ic_s_rd),
      .m_axi_wr(axi_ic_m_wr),
      .m_axi_rd(axi_ic_m_rd)
  );

  // =================
  // Connectivity Core
  // =================
  /* PCIe Controller */
  wire [  4:0] pcie_ltssm;
  wire         pcie_tl_rx_sop;
  wire         pcie_tl_rx_eop;
  wire [255:0] pcie_tl_rx_data;
  wire [  7:0] pcie_tl_rx_valid;
  wire [  5:0] pcie_tl_rx_bardec;
  wire [  7:0] pcie_tl_rx_err;
  wire         pcie_tl_rx_wait;
  wire         pcie_tl_rx_masknp;
  wire         pcie_tl_tx_sop;
  wire         pcie_tl_tx_eop;
  wire [255:0] pcie_tl_tx_data;
  wire [  7:0] pcie_tl_tx_valid;
  wire         pcie_tl_tx_wait;
  wire         pcie_tl_drp_clk;
  wire [ 23:0] pcie_tl_drp_addr;
  wire         pcie_tl_drp_ready;
  wire [  7:0] pcie_tl_drp_strb;
  wire         pcie_tl_drp_resp;
  wire         pcie_tl_drp_wr;
  wire [ 31:0] pcie_tl_drp_wrdata;
  wire         pcie_tl_drp_rd;
  wire [ 31:0] pcie_tl_drp_rddata;
  wire         pcie_tl_drp_rd_valid;
  wire         pcie_tl_int_req;
  wire         pcie_tl_int_ack;
  wire         pcie_tl_int_status;
  wire [  4:0] pcie_tl_int_msinum;
  wire [ 12:0] pcie_tl_cfg_busdev;

  SerDes_Top u_pcie_ip (
      .PCIE_Controller_Top_pcie_rstn_i(rst_n),
      .PCIE_Controller_Top_pcie_tl_clk_i(tlp_clk),
      .PCIE_Controller_Top_pcie_linkup_o(pcie_linkup),
      .PCIE_Controller_Top_pcie_ltssm_o(pcie_ltssm),
      .PCIE_Controller_Top_pcie_tl_rx_sop_o(pcie_tl_rx_sop),
      .PCIE_Controller_Top_pcie_tl_rx_eop_o(pcie_tl_rx_eop),
      .PCIE_Controller_Top_pcie_tl_rx_data_o(pcie_tl_rx_data),
      .PCIE_Controller_Top_pcie_tl_rx_valid_o(pcie_tl_rx_valid),
      .PCIE_Controller_Top_pcie_tl_rx_bardec_o(pcie_tl_rx_bardec),
      .PCIE_Controller_Top_pcie_tl_rx_wait_i(pcie_tl_rx_wait),
      .PCIE_Controller_Top_pcie_tl_rx_masknp_i(pcie_tl_rx_masknp),
      .PCIE_Controller_Top_pcie_tl_rx_err_o(pcie_tl_rx_err),
      .PCIE_Controller_Top_pcie_tl_tx_sop_i(pcie_tl_tx_sop),
      .PCIE_Controller_Top_pcie_tl_tx_eop_i(pcie_tl_tx_eop),
      .PCIE_Controller_Top_pcie_tl_tx_data_i(pcie_tl_tx_data),
      .PCIE_Controller_Top_pcie_tl_tx_valid_i(pcie_tl_tx_valid),
      .PCIE_Controller_Top_pcie_tl_tx_wait_o(pcie_tl_tx_wait),
      .PCIE_Controller_Top_pcie_tl_drp_clk_o(pcie_tl_drp_clk),
      .PCIE_Controller_Top_pcie_tl_drp_addr_i(pcie_tl_drp_addr),
      .PCIE_Controller_Top_pcie_tl_drp_ready_o(pcie_tl_drp_ready),
      .PCIE_Controller_Top_pcie_tl_drp_resp_o(pcie_tl_drp_resp),
      .PCIE_Controller_Top_pcie_tl_drp_strb_i(pcie_tl_drp_strb),
      .PCIE_Controller_Top_pcie_tl_drp_wr_i(pcie_tl_drp_wr),
      .PCIE_Controller_Top_pcie_tl_drp_wrdata_i(pcie_tl_drp_wrdata),
      .PCIE_Controller_Top_pcie_tl_drp_rd_i(pcie_tl_drp_rd),
      .PCIE_Controller_Top_pcie_tl_drp_rddata_o(pcie_tl_drp_rddata),
      .PCIE_Controller_Top_pcie_tl_drp_rd_valid_o(pcie_tl_drp_rd_valid),
      .PCIE_Controller_Top_pcie_tl_int_req_i(pcie_tl_int_req),
      .PCIE_Controller_Top_pcie_tl_int_ack_o(pcie_tl_int_ack),
      .PCIE_Controller_Top_pcie_tl_int_status_i(pcie_tl_int_status),
      .PCIE_Controller_Top_pcie_tl_int_msinum_i(pcie_tl_int_msinum),
      .PCIE_Controller_Top_pcie_tl_cfg_busdev_o(pcie_tl_cfg_busdev)
  );

  /* PCIe SGDMA */
  wire [63:0] h2c_overhead;
  wire        h2c_run;
  wire        c2h_run;
  // AXI-Stream Data
  taxi_axis_if #(
      .DATA_W (AXI_DATA_WIDTH),
      .KEEP_EN(1),
      .KEEP_W (AXI_STRB_WIDTH),
      .LAST_EN(1)
  ) axis_pcie_h2c ();
  taxi_axis_if #(
      .DATA_W (AXI_DATA_WIDTH),
      .KEEP_EN(1),
      .KEEP_W (AXI_STRB_WIDTH),
      .LAST_EN(1)
  ) axis_pcie_c2h ();
  // BAR2
  wire        user_cs;
  wire [63:0] user_address;
  wire        user_rw;
  wire [31:0] user_wr_data;
  wire        user_rd_valid;
  wire [31:0] user_rd_data;

  Pcie_Sgdma_Top u_pcie_sgdma (
      .pcie_rstn(rst_n),
      .clk(tlp_clk),
      .pcie_tl_rx_sop(pcie_tl_rx_sop),
      .pcie_tl_rx_eop(pcie_tl_rx_eop),
      .pcie_tl_rx_data(pcie_tl_rx_data),
      .pcie_tl_rx_valid(pcie_tl_rx_valid),
      .pcie_tl_rx_bardec(pcie_tl_rx_bardec),
      .pcie_tl_rx_err(pcie_tl_rx_err),
      .pcie_tl_rx_wait(pcie_tl_rx_wait),
      .pcie_tl_rx_masknp(pcie_tl_rx_masknp),
      .pcie_tl_tx_sop(pcie_tl_tx_sop),
      .pcie_tl_tx_eop(pcie_tl_tx_eop),
      .pcie_tl_tx_data(pcie_tl_tx_data),
      .pcie_tl_tx_valid(pcie_tl_tx_valid),
      .pcie_tl_tx_wait(pcie_tl_tx_wait),
      .pcie_tl_int_status(pcie_tl_int_status),
      .pcie_tl_int_req(pcie_tl_int_req),
      .pcie_tl_int_msinum(pcie_tl_int_msinum),
      .pcie_tl_int_ack(pcie_tl_int_ack),
      .pcie_tl_drp_clk(pcie_tl_drp_clk),
      .pcie_tl_drp_addr(pcie_tl_drp_addr),
      .pcie_tl_drp_wr(pcie_tl_drp_wr),
      .pcie_tl_drp_wrdata(pcie_tl_drp_wrdata),
      .pcie_tl_drp_strb(pcie_tl_drp_strb),
      .pcie_tl_drp_rd(pcie_tl_drp_rd),
      .pcie_tl_drp_ready(pcie_tl_drp_ready),
      .pcie_tl_drp_rd_valid(pcie_tl_drp_rd_valid),
      .pcie_tl_drp_rddata(pcie_tl_drp_rddata),
      .pcie_tl_drp_resp(pcie_tl_drp_resp),
      .pcie_ltssm(pcie_ltssm),
      .pcie_linkup(pcie_linkup),
      .pcie_tl_cfg_busdev(pcie_tl_cfg_busdev),
      .m_axis_h2c_tready(axis_pcie_h2c.tready),
      .m_axis_h2c_tvalid(axis_pcie_h2c.tvalid),
      .m_axis_h2c_tdata(axis_pcie_h2c.tdata),
      .m_axis_h2c_tlast(axis_pcie_h2c.tlast),
      .m_axis_h2c_tkeep(axis_pcie_h2c.tkeep),
      .h2c_overhead(h2c_overhead),
      .s_axis_c2h_tready(axis_pcie_c2h.tready),
      .s_axis_c2h_tvalid(axis_pcie_c2h.tvalid),
      .s_axis_c2h_tlast(axis_pcie_c2h.tlast),
      .s_axis_c2h_tdata(axis_pcie_c2h.tdata),
      .s_axis_c2h_tkeep(axis_pcie_c2h.tkeep),
      .c2h_overhead_valid(1'b0),
      .c2h_overhead_data(64'd0),
      .user_cs(user_cs),
      .user_address(user_address),
      .user_rw(user_rw),
      .user_wr_data(user_wr_data),
      .user_rd_valid(user_rd_valid),
      .user_rd_data(user_rd_data),
      .h2c_run(h2c_run),
      .c2h_run(c2h_run)
  );

  /* Manager Logic (BAR2, Logic Core, AXI DMA Descriptors) */
  reg [63:0] h2c_overhead_reg;
  // AXI DMA Descriptors
  taxi_dma_desc_if #(
      .SRC_ADDR_W(AXI_ADDR_WIDTH),
      .DST_ADDR_W(AXI_ADDR_WIDTH),
      .LEN_W(AXI_LEN_WIDTH),
      .TAG_W(8)
  ) desc_pcie_rd ();
  taxi_dma_desc_if #(
      .SRC_ADDR_W(AXI_ADDR_WIDTH),
      .DST_ADDR_W(AXI_ADDR_WIDTH),
      .LEN_W(AXI_LEN_WIDTH),
      .TAG_W(8)
  ) desc_pcie_wr ();
  // Logic Core Config
  wire [AXI_ADDR_WIDTH-1:0] lconv_cfg_read_addr;
  wire [AXI_ADDR_WIDTH-1:0] lconv_cfg_write_addr;
  wire [ AXI_LEN_WIDTH-1:0] lconv_cfg_len;
  wire                      lconv_run;
  wire                      lconv_done;

  always @(posedge tlp_clk or negedge rst_n) begin
    if (!rst_n) begin
      h2c_overhead_reg <= 64'd0;
    end else begin
      if (axis_pcie_h2c.tvalid) begin
        h2c_overhead_reg <= h2c_overhead;
      end
    end
  end

  manager_logic #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_LEN_WIDTH (AXI_LEN_WIDTH)
  ) u_manager_logic (
      .clk(tlp_clk),
      .rst_n(rst_n),
      .user_cs(user_cs),
      .user_address(user_address),
      .user_rw(user_rw),
      .user_wr_data(user_wr_data),
      .user_rd_valid(user_rd_valid),
      .user_rd_data(user_rd_data),
      .h2c_overhead_reg(h2c_overhead_reg),
      .desc_h2c(desc_pcie_wr),
      .desc_c2h(desc_pcie_rd),
      .lcore_read_addr(lconv_cfg_read_addr),
      .lcore_write_addr(lconv_cfg_write_addr),
      .lcore_len(lconv_cfg_len),
      .lcore_run(lconv_run),
      .lcore_done(lconv_done)
  );

  /* Async FIFO */
  // AXI-Stream h2c
  taxi_axis_if #(
      .DATA_W (AXI_DATA_WIDTH),
      .KEEP_EN(1),
      .KEEP_W (AXI_STRB_WIDTH),
      .LAST_EN(1)
  ) axis_dma_h2c ();

  taxi_axis_async_fifo #(
      .DEPTH(AXI_FIFO_DEPTH)
  ) u_axis_fifo_h2c (
      .s_clk (tlp_clk),
      .s_rst (~rst_n),
      .s_axis(axis_pcie_h2c),
      .m_clk (ui_clk),
      .m_rst (ui_rst),
      .m_axis(axis_dma_h2c)
  );

  // AXI-Stream c2h
  taxi_axis_if #(
      .DATA_W (AXI_DATA_WIDTH),
      .KEEP_EN(1),
      .KEEP_W (AXI_STRB_WIDTH),
      .LAST_EN(1)
  ) axis_dma_c2h ();

  taxi_axis_async_fifo #(
      .DEPTH(AXI_FIFO_DEPTH)
  ) u_axis_fifo_c2h (
      .s_clk (ui_clk),
      .s_rst (ui_rst),
      .s_axis(axis_dma_c2h),
      .m_clk (tlp_clk),
      .m_rst (~rst_n),
      .m_axis(axis_pcie_c2h)
  );

  /* AXI DMA */
  taxi_axi_dma #(
      .AXI_MAX_BURST_LEN(AXI_BURST_LEN),
      .UNALIGNED_EN(0)
  ) u_axi_dma_pcie_sgdma (
      .clk(ui_clk),
      .rst(ui_rst),
      .rd_desc_req(desc_pcie_rd),
      .rd_desc_sts(desc_pcie_rd),
      .wr_desc_req(desc_pcie_wr),
      .wr_desc_sts(desc_pcie_wr),
      .m_axis_rd_data(axis_dma_c2h),
      .s_axis_wr_data(axis_dma_h2c),
      .m_axi_wr(axi_ic_s_wr[0]),
      .m_axi_rd(axi_ic_s_rd[0]),
      .read_enable(1'b1),
      .write_enable(1'b1),
      .write_abort(1'b0)
  );

  // ==========
  // Logic Core
  // ==========
  /* Convolution */
  // AXI DMA Descriptors
  taxi_dma_desc_if #(
      .SRC_ADDR_W(AXI_ADDR_WIDTH),
      .DST_ADDR_W(AXI_ADDR_WIDTH),
      .LEN_W(AXI_LEN_WIDTH),
      .TAG_W(8)
  ) desc_lconv_rd ();
  taxi_dma_desc_if #(
      .SRC_ADDR_W(AXI_ADDR_WIDTH),
      .DST_ADDR_W(AXI_ADDR_WIDTH),
      .LEN_W(AXI_LEN_WIDTH),
      .TAG_W(8)
  ) desc_lconv_wr ();
  // AXI-Stream Data
  taxi_axis_if #(
      .DATA_W (AXI_DATA_WIDTH),
      .KEEP_EN(1),
      .KEEP_W (AXI_STRB_WIDTH),
      .LAST_EN(1)
  ) axis_lconv_rx ();
  taxi_axis_if #(
      .DATA_W (AXI_DATA_WIDTH),
      .KEEP_EN(1),
      .KEEP_W (AXI_STRB_WIDTH),
      .LAST_EN(1)
  ) axis_lconv_tx ();

  logic_conv #(
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_LEN_WIDTH(AXI_LEN_WIDTH),
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
      .IMAGE_WIDTH(256),
      .IMAGE_HEIGHT(8),
      .KERNEL_SIZE(3)
  ) u_logic_conv (
      .clk(ui_clk),
      .rst_n(~ui_rst),
      .cfg_read_addr(lconv_cfg_read_addr),
      .cfg_write_addr(lconv_cfg_write_addr),
      .cfg_len(lconv_cfg_len),
      .rd_desc_req(desc_lconv_rd),
      .wr_desc_req(desc_lconv_wr),
      .wr_desc_sts(desc_lconv_wr),
      .s_axis_rx(axis_lconv_rx),
      .m_axis_tx(axis_lconv_tx),
      .run(lconv_run),
      .done(lconv_done)
  );

  /* AXI DMA */
  taxi_axi_dma #(
      .AXI_MAX_BURST_LEN(AXI_BURST_LEN),
      .UNALIGNED_EN(0)
  ) u_axi_dma_logic_adder (
      .clk(ui_clk),
      .rst(ui_rst),
      .rd_desc_req(desc_lconv_rd),
      .rd_desc_sts(desc_lconv_rd),
      .wr_desc_req(desc_lconv_wr),
      .wr_desc_sts(desc_lconv_wr),
      .m_axis_rd_data(axis_lconv_rx),
      .s_axis_wr_data(axis_lconv_tx),
      .m_axi_wr(axi_ic_s_wr[1]),
      .m_axi_rd(axi_ic_s_rd[1]),
      .read_enable(1'b1),
      .write_enable(1'b1),
      .write_abort(1'b0)
  );

  // ===========
  // Memory Core
  // ===========
  /* DDR3 */
  assign axi_ic_m_wr[0].buser = 1'b0;
  assign axi_ic_m_rd[0].ruser = 1'b0;

  DDR3_Memory_Interface_Top u_ddr3 (
      .clk(ddr_in_clk),
      .pll_stop(pll_stop),
      .memory_clk(memory_clk),
      .pll_lock(pll_lock),
      .rst_n(rst_n),
      .clk_out(ddr_out_clk),
      .ddr_rst(ddr_out_rst),
      .init_calib_complete(ddr_init),
      .s_axi_awvalid(axi_ic_m_wr[0].awvalid),
      .s_axi_awready(axi_ic_m_wr[0].awready),
      .s_axi_awid(axi_ic_m_wr[0].awid),
      .s_axi_awaddr(axi_ic_m_wr[0].awaddr),
      .s_axi_awlen(axi_ic_m_wr[0].awlen),
      .s_axi_awsize(axi_ic_m_wr[0].awsize),
      .s_axi_awburst(axi_ic_m_wr[0].awburst),
      .s_axi_wvalid(axi_ic_m_wr[0].wvalid),
      .s_axi_wready(axi_ic_m_wr[0].wready),
      .s_axi_wdata(axi_ic_m_wr[0].wdata),
      .s_axi_wstrb(axi_ic_m_wr[0].wstrb),
      .s_axi_wlast(axi_ic_m_wr[0].wlast),
      .s_axi_bvalid(axi_ic_m_wr[0].bvalid),
      .s_axi_bready(axi_ic_m_wr[0].bready),
      .s_axi_bresp(axi_ic_m_wr[0].bresp),
      .s_axi_bid(axi_ic_m_wr[0].bid),
      .s_axi_arvalid(axi_ic_m_rd[0].arvalid),
      .s_axi_arready(axi_ic_m_rd[0].arready),
      .s_axi_arid(axi_ic_m_rd[0].arid),
      .s_axi_araddr(axi_ic_m_rd[0].araddr),
      .s_axi_arlen(axi_ic_m_rd[0].arlen),
      .s_axi_arsize(axi_ic_m_rd[0].arsize),
      .s_axi_arburst(axi_ic_m_rd[0].arburst),
      .s_axi_rvalid(axi_ic_m_rd[0].rvalid),
      .s_axi_rready(axi_ic_m_rd[0].rready),
      .s_axi_rdata(axi_ic_m_rd[0].rdata),
      .s_axi_rresp(axi_ic_m_rd[0].rresp),
      .s_axi_rid(axi_ic_m_rd[0].rid),
      .s_axi_rlast(axi_ic_m_rd[0].rlast),
      .sr_req(1'b0),
      .ref_req(1'b0),
      .burst(1'b1),
      .O_ddr_addr(ddr_addr),
      .O_ddr_ba(ddr_ba),
      .O_ddr_cs_n(ddr_cs_n),
      .O_ddr_ras_n(ddr_ras_n),
      .O_ddr_cas_n(ddr_cas_n),
      .O_ddr_we_n(ddr_we_n),
      .O_ddr_clk(ddr_clk),
      .O_ddr_clk_n(ddr_clk_n),
      .O_ddr_cke(ddr_cke),
      .O_ddr_odt(ddr_odt),
      .O_ddr_reset_n(ddr_reset_n),
      .O_ddr_dqm(ddr_dqm),
      .IO_ddr_dq(ddr_dq),
      .IO_ddr_dqs(ddr_dqs),
      .IO_ddr_dqs_n(ddr_dqs_n)
  );

  // ====
  // Leds
  // ====
  assign led[0] = ~run_cnt[RUN_DLY];
  assign led[1] = ~perst_cnt[PERST_DLY];
  assign led[2] = ~pcie_start;
  assign led[3] = ~pcie_linkup_r;
  assign led[4] = ~ddr_init;
  assign led[5] = ~h2c_run;

endmodule
