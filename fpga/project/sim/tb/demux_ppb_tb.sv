`timescale 1ns / 1ps

module demux_ppb_tb ();
  parameter int M = 3;
  parameter int IMAGE_WIDTH = 64;
  parameter int RD_LATENCY = 2;
  parameter int KERNEL_SIZE = 3;

  localparam int N = M + 1;
  localparam int ADDR_W = $clog2(IMAGE_WIDTH);
  localparam int SEL_W = $clog2(N);

  localparam int IMAGE_WIDTH_REAL = IMAGE_WIDTH - 2 * (KERNEL_SIZE / 2);
  localparam int LATENCY_ADD = RD_LATENCY + KERNEL_SIZE + 1;

  logic clk;
  logic rst_n;

  logic       s_ready;
  logic       s_valid;
  logic       s_last;
  logic [7:0] s_data;

  logic       demux_ready;
  logic       demux_valid;
  logic       demux_last;
  logic [7:0] demux_data;

  logic [       M:0] write_en;
  logic [ SEL_W-1:0] write_sel;
  logic [ADDR_W-1:0] addr;

  demux #(
    .M          (M),
    .IMAGE_WIDTH(IMAGE_WIDTH),
    .RD_LATENCY (RD_LATENCY)
  ) u_demux_1_to_m1 (
    .clk      (clk),
    .rst_n    (rst_n),
    .s_valid  (s_valid),
    .s_last   (s_last),
    .s_data   (s_data),
    .s_ready  (s_ready),
    .m_ready  (demux_ready),
    .m_valid  (demux_valid),
    .m_last   (demux_last),
    .m_data   (demux_data),
    .write_en (write_en),
    .write_sel(write_sel),
    .addr     (addr)
  );

  logic [M:0] line_valid;
  logic [7:0] line_data  [N];

  for (genvar i = 0; i < N; i++) begin : gen_line_buffers
    line_buffer #(
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .RD_LATENCY (RD_LATENCY)
    ) u_line_buffer (
      .clk       (clk),
      .rst_n     (rst_n),
      .addr      (addr),
      .rx_data   (demux_data),
      .tx_data   (line_data[i]),
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
    .s_data    (line_data),
    .s_ready   (demux_ready),
    .m_ready   (switch_ready),
    .m_valid   (switch_valid),
    .m_last    (switch_last),
    .m_data    (switch_data)
  );

  logic        ker_valid;
  logic [31:0] ker_data;

  logic         conv_ready;
  logic [M-1:0] conv_valid;
  logic [  7:0] conv_data  [M];

  for (genvar i = 0; i < M; i++) begin : gen_conv
    conv1d #(
      .KERNEL_SIZE(KERNEL_SIZE)
    ) u_conv1d (
      .clk      (clk),
      .rst_n    (rst_n),
      .ker_valid(ker_valid),
      .ker_data (ker_data),
      .s_valid  (switch_valid),
      .s_last   (switch_last),
      .s_data   (switch_data[i]),
      .m_ready  (conv_ready),
      .m_valid  (conv_valid[i]),
      .m_data   (conv_data[i])
    );
  end

  assign switch_ready = 1'b1;

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

  logic done_ready;
  logic done_sel;
  logic done;

  logic              rd_req;
  logic              rd_sel;
  logic [ADDR_W-1:0] rd_addr;

  ping_pong_buffer #(
    .IMAGE_WIDTH(IMAGE_WIDTH_REAL),
    .RD_LATENCY (RD_LATENCY)
  ) u_ppb (
    .clk       (clk),
    .rst_n     (rst_n),
    .s_valid   (add_valid),
    .s_data    (add_data),
    .s_ready   (add_ready),
    .m_valid   (ppb_valid),
    .m_data    (ppb_data),
    .rd_req    (rd_req),
    .rd_sel    (rd_sel),
    .rd_addr   (rd_addr),
    .done_ready(done_ready),
    .done      (done),
    .done_sel  (done_sel)
  );

  int errors;
  int checks;

  task check_value(input logic [63:0] got, exp, input int cycle, input string tag);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s [%0d]: got=%0h exp=%0h", tag, cycle, got, exp);
    end
  endtask

  function automatic logic [7:0] expect_sum(input int col);
    int sum;
    sum = M * (KERNEL_SIZE * col + KERNEL_SIZE * (KERNEL_SIZE - 1) / 2);
    return (sum > 255) ? 8'd255 : sum[7:0];
  endfunction

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task reset_dut();
    @(negedge clk);
    rst_n      = 1'b0;
    ker_valid  = 1'b0;
    ker_data   = 32'h3f800000;  // 1.0
    s_valid    = 1'b0;
    s_last     = 1'b0;
    s_data     = '0;
    rd_req     = 1'b0;
    rd_sel     = 1'b0;
    rd_addr    = '0;
    done_ready = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  int exp_pixel_cnt;

  initial begin
    if (M != KERNEL_SIZE || KERNEL_SIZE < 2 || IMAGE_WIDTH <= KERNEL_SIZE ||
        IMAGE_WIDTH > 64 || RD_LATENCY < 1) begin
      $fatal(
        1,
        "Invalid parameters: M=KERNEL_SIZE>=2, KERNEL_SIZE<IMAGE_WIDTH<=64 and RD_LATENCY>=1");
    end
    reset_dut();

    $display("Test 1: demux -> switch -> conv1d x%0d -> adder -> ping-pong buffer",
             M);
    $display("Kernel loading");
    @(negedge clk);
    ker_valid = 1'b1;
    repeat (KERNEL_SIZE) @(posedge clk);
    @(negedge clk);
    ker_valid = 1'b0;

    $display("Line buffer fill");
    for (int row = 0; row < M; row++) begin
      for (int col = 0; col < IMAGE_WIDTH; col++) begin
        @(negedge clk);
        s_valid = 1'b1;
        s_data  = col[7:0];

        @(posedge clk);
        check_value(s_ready, 1'b1, row * IMAGE_WIDTH + col, "s_ready");
        check_value(switch_valid, 1'b0, row * IMAGE_WIDTH + col, "switch_valid");
      end
    end

    $display("Convolution output");
    for (int col = 0; col < IMAGE_WIDTH_REAL + LATENCY_ADD; col++) begin
      @(negedge clk);
      s_valid = (col < IMAGE_WIDTH);
      s_data  = col[7:0];

      @(posedge clk);
      check_value(switch_valid,
                  (col >= RD_LATENCY && col < IMAGE_WIDTH + RD_LATENCY), col,
                  "switch_valid");
      check_value(add_valid,
                  (col >= LATENCY_ADD && col < IMAGE_WIDTH_REAL + LATENCY_ADD), col,
                  "add_valid");

      if (add_valid && add_ready) begin
        check_value(add_data, expect_sum(exp_pixel_cnt), exp_pixel_cnt, "add_data");
        exp_pixel_cnt++;
      end
    end

    check_value(exp_pixel_cnt, IMAGE_WIDTH_REAL, IMAGE_WIDTH_REAL + LATENCY_ADD,
                "exp_pixel_cnt");

    @(posedge clk);
    check_value(done, 1'b1, 0, "done");
    check_value(done_sel, 1'b0, 0, "done_sel");

    $display("Test 2: Convolution result readback");
    for (int cycle = 0; cycle < IMAGE_WIDTH_REAL + RD_LATENCY; cycle++) begin
      @(negedge clk);
      rd_sel  = done_sel;
      rd_addr = (cycle < IMAGE_WIDTH_REAL) ? cycle[ADDR_W-1:0] : '0;
      rd_req  = (cycle < IMAGE_WIDTH_REAL);

      @(posedge clk);
      check_value(ppb_valid, cycle >= RD_LATENCY, cycle, "ppb_valid");
      if (cycle >= RD_LATENCY) begin
        check_value(ppb_data, expect_sum(cycle - RD_LATENCY), cycle - RD_LATENCY,
                    "ppb_data");
      end
    end

    @(posedge clk);
    check_value(ppb_valid, 1'b0, IMAGE_WIDTH_REAL + RD_LATENCY, "ppb_valid");

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
