`timescale 1ns / 1ps

module grayscale_stream_tb ();
  parameter int AXI_DATA_WIDTH = 256;
  parameter int AXI_ADDR_WIDTH = 29;
  parameter int AXI_LEN_WIDTH = 20;
  parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
  parameter int KERNEL_SIZE = 3;
  parameter int IMAGE_WIDTH = 62;
  parameter int IMAGE_HEIGHT = 6;

  localparam int PAD = KERNEL_SIZE / 2;
  localparam int ROW_LEN = IMAGE_WIDTH - 2 * PAD;
  localparam int BYTES_PER_WORD = AXI_DATA_WIDTH / 8;
  localparam int BEATS_PER_ROW = (ROW_LEN + BYTES_PER_WORD - 1) / BYTES_PER_WORD;

  logic clk;
  logic rst_n;

  logic [AXI_ADDR_WIDTH-1:0] cfg_write_addr;

  logic       s_valid;
  logic [7:0] s_data;

  taxi_dma_desc_if #(
    .DST_ADDR_W(AXI_ADDR_WIDTH),
    .LEN_W     (AXI_LEN_WIDTH)
  ) wr_desc_req ();
  taxi_axis_if #(
    .DATA_W(AXI_DATA_WIDTH),
    .KEEP_W(AXI_STRB_WIDTH)
  ) m_axis_tx ();

  logic ppb_done_ready;
  logic ppb_done_sel;
  logic ppb_done;

  logic                       rd_req;
  logic                       rd_sel;
  logic [$clog2(ROW_LEN)-1:0] rd_addr;

  grayscale_stream #(
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_LEN_WIDTH (AXI_LEN_WIDTH),
    .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
    .KERNEL_SIZE   (KERNEL_SIZE),
    .IMAGE_WIDTH   (IMAGE_WIDTH),
    .IMAGE_HEIGHT  (IMAGE_HEIGHT)
  ) dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .cfg_write_addr(cfg_write_addr),
    .s_valid       (s_valid),
    .s_data        (s_data),
    .wr_desc_req   (wr_desc_req),
    .m_axis_tx     (m_axis_tx),
    .ppb_done      (ppb_done),
    .ppb_done_sel  (ppb_done_sel),
    .ppb_done_ready(ppb_done_ready),
    .rd_req        (rd_req),
    .rd_sel        (rd_sel),
    .rd_addr       (rd_addr)
  );

  int errors;
  int checks;

  task check_value(input logic [63:0] got, input logic [63:0] exp, input int cycle,
                   input string tag);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s [%0d]: got=%0h exp=%0h", tag, cycle, got, exp);
    end
  endtask

  task reset_dut();
    @(negedge clk);
    rst_n                 = 1'b0;
    cfg_write_addr        = 'h1000;
    s_valid               = 1'b0;
    s_data                = '0;
    wr_desc_req.req_ready = 1'b0;
    m_axis_tx.tready      = 1'b0;
    ppb_done              = 1'b0;
    ppb_done_sel          = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  logic [AXI_STRB_WIDTH-1:0] exp_keep;
  logic [AXI_DATA_WIDTH-1:0] exp_data;
  int                        exp_byte_cnt;

  initial begin
    int col;
    if (ROW_LEN < 2 || ROW_LEN > 256 || AXI_DATA_WIDTH < 16 ||
        AXI_DATA_WIDTH % 8 != 0 || AXI_STRB_WIDTH != BYTES_PER_WORD) begin
      $fatal(
        1,
        "Invalid parameters: 2 <= ROW_LEN <= 256, AXI_DATA_WIDTH >= 16 and a multiple of 8, AXI_STRB_WIDTH == BYTES_PER_WORD");
    end
    reset_dut();

    for (int row = 0; row < 2; row++) begin
      $display(
        "Test %0d: Row packing, bank selection, destination advancement and AXI stalls",
        row + 1);
      $display("Completed bank");
      @(negedge clk);
      ppb_done     = 1'b1;
      ppb_done_sel = row[0];

      @(posedge clk);
      check_value(ppb_done_ready, 1'b1, row, "ppb_done_ready");

      @(negedge clk);
      ppb_done = 1'b0;

      $display("DMA descriptor");
      for (int cycle = 0; cycle <= 2 * row; cycle++) begin
        @(posedge clk);
        check_value(wr_desc_req.req_valid, 1'b1, cycle, "wr_desc_req.req_valid");
        check_value(wr_desc_req.req_dst_addr,
                    cfg_write_addr + (row + PAD) * IMAGE_WIDTH + PAD, cycle,
                    "wr_desc_req.req_dst_addr");
        check_value(wr_desc_req.req_len, ROW_LEN, cycle, "wr_desc_req.req_len");

        check_value(rd_sel, row, cycle, "rd_sel");
        check_value(rd_req, 1'b0, cycle, "rd_req");
      end

      @(negedge clk);
      wr_desc_req.req_ready = 1'b1;

      @(negedge clk);
      wr_desc_req.req_ready = 1'b0;

      for (int beat = 0; beat < BEATS_PER_ROW; beat++) begin
        $display("Grayscale input beat %0d", beat);
        exp_data = '0;
        exp_keep = 'b0;
        exp_byte_cnt = (ROW_LEN - beat * BYTES_PER_WORD < BYTES_PER_WORD) ?
                ROW_LEN - beat * BYTES_PER_WORD : BYTES_PER_WORD;

        for (int byte_idx = 0; byte_idx < exp_byte_cnt; byte_idx++) begin
          col = beat * BYTES_PER_WORD + byte_idx;
          check_value(rd_addr, col, col, "rd_addr");

          @(negedge clk);
          s_valid                 = 1'b1;
          s_data                  = 8'(row * 64 + col);
          exp_data[byte_idx*8+:8] = s_data;
          exp_keep[byte_idx]      = 1'b1;
          @(posedge clk);

          @(negedge clk);
          s_valid = 1'b0;
        end

        $display("AXI output beat %0d", beat);
        repeat (2) @(posedge clk);
        for (int cycle = 0; cycle <= 2 * row; cycle++) begin
          check_value(m_axis_tx.tvalid, 1'b1, beat, "m_axis_tx.tvalid");
          check_value(m_axis_tx.tlast, beat == BEATS_PER_ROW - 1, beat,
                      "m_axis_tx.tlast");
          check_value(m_axis_tx.tkeep, exp_keep, beat, "m_axis_tx.tkeep");

          for (int byte_idx = 0; byte_idx < BYTES_PER_WORD; byte_idx++) begin
            check_value(m_axis_tx.tdata[byte_idx*8+:8], exp_data[byte_idx*8+:8],
                        beat * BYTES_PER_WORD + byte_idx, "m_axis_tx.tdata");
          end
        end

        @(negedge clk);
        m_axis_tx.tready = 1'b1;
        @(posedge clk);

        @(negedge clk);
        m_axis_tx.tready = 1'b0;
      end

      $display("Row completion");
      @(posedge clk);
      check_value(ppb_done_ready, 1'b1, row, "ppb_done_ready");
      check_value(m_axis_tx.tvalid, 1'b0, row, "m_axis_tx.tvalid");
    end

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
