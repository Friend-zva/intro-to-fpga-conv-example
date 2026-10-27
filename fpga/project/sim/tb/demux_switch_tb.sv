`timescale 1ns / 1ps

module demux_switch_tb ();
  parameter int M = 3;
  parameter int IMAGE_WIDTH = 64;
  parameter int RD_LATENCY = 2;

  localparam int N = M + 1;
  localparam int ADDR_W = $clog2(IMAGE_WIDTH);
  localparam int SEL_W = $clog2(N);

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
  logic [7:0] lb_data    [M+1];

  for (genvar i = 0; i < N; i++) begin : gen_buffers
    line_buffer #(
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .RD_LATENCY (RD_LATENCY)
    ) u_line_buffer (
      .clk       (clk),
      .rst_n     (rst_n),
      .addr      (addr),
      .rx_data   (demux_data),
      .tx_data   (lb_data[i]),
      .write_en  (write_en[i]),
      .line_valid(line_valid[i])
    );
  end

  logic       m_ready;
  logic       m_valid;
  logic [7:0] m_data  [M];

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
    .m_ready   (m_ready),
    .m_valid   (m_valid),
    .m_data    (m_data)
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

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task reset_dut();
    @(negedge clk);
    rst_n   = 1'b0;
    s_valid = 1'b0;
    s_last  = 1'b0;
    s_data  = '0;
    m_ready = 1'b1;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  logic [7:0] exp_data;
  int         exp_demux_line;

  initial begin
    if (M != 3 || IMAGE_WIDTH != 64 || RD_LATENCY != 2) begin
      $fatal(1, "Invalid parameters: M=3, IMAGE_WIDTH=64 and RD_LATENCY=2");
    end
    reset_dut();

    $display("Test 1: demux -> line_buffer x%0d -> switch", N);
    for (int row = 0; row < N; row++) begin
      for (int col = 0; col < IMAGE_WIDTH; col++) begin
        @(negedge clk);
        s_valid = 1'b1;
        s_data  = {col[5:0], row[1:0]};

        @(posedge clk);
        check_value(s_ready, 1'b1, col, "s_ready");
        check_value(demux_valid, 1'b1, col, "demux_valid");
        check_value(m_valid, (row == M && col >= RD_LATENCY), col, "m_valid");
        if (m_valid) begin
          for (int line = 0; line < M; line++) begin
            exp_data = col - RD_LATENCY;
            check_value(m_data[line], {exp_data[5:0], line[1:0]},
                        row * IMAGE_WIDTH + col, "m_data");
          end
        end
      end
    end

    $display("Test 2: Last line");
    for (int col = 0; col < IMAGE_WIDTH; col++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_last  = (col == IMAGE_WIDTH - 1);
      s_data  = {col[5:0], 2'b00};

      @(posedge clk);
      check_value(s_ready, 1'b1, col, "s_ready");
      check_value(demux_valid, 1'b1, col, "demux_valid");
      check_value(m_valid, 1'b1, col, "m_valid");
      for (int line = 0; line < M; line++) begin
        exp_data       = ((col < RD_LATENCY) ? IMAGE_WIDTH : 0) + col - RD_LATENCY;
        exp_demux_line = (col < RD_LATENCY) ? line : (line + 1);
        check_value(m_data[line], {exp_data[5:0], exp_demux_line[1:0]}, col,
                    "m_data");
      end
    end
    @(negedge clk);
    s_valid = 1'b0;
    s_last  = 1'b0;

    for (int col = 0; col < IMAGE_WIDTH; col++) begin
      @(posedge clk);
      check_value(s_ready, 1'b0, col, "s_ready");
      check_value(demux_valid, 1'b1, col, "demux_valid");
      check_value(demux_last, (col == IMAGE_WIDTH - 1), col, "demux_last");
      check_value(m_valid, 1'b1, col, "m_valid");

      for (int line = 0; line < M; line++) begin
        exp_data       = ((col < RD_LATENCY) ? IMAGE_WIDTH : 0) + col - RD_LATENCY;
        exp_demux_line = (col < RD_LATENCY) ? (line + 1) : (line + 2);
        check_value(m_data[line], {exp_data[5:0], exp_demux_line[1:0]}, col,
                    "m_data");
      end
    end

    for (int tail = 0; tail < RD_LATENCY; tail++) begin
      @(posedge clk);
      check_value(s_ready, 1'b0, tail, "s_ready");
      check_value(demux_valid, 1'b0, tail, "demux_valid");
      check_value(m_valid, 1'b1, tail, "m_valid");

      for (int line = 0; line < M; line++) begin
        exp_data       = IMAGE_WIDTH - RD_LATENCY + tail;
        exp_demux_line = line + 2;
        check_value(m_data[line], {exp_data[5:0], exp_demux_line[1:0]}, tail,
                    "m_data");
      end
    end
    @(posedge clk);
    check_value(m_valid, 1'b0, 0, "m_valid");

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
