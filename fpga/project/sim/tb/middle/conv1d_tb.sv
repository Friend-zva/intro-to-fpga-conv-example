`timescale 1ns / 1ps

module conv1d_tb ();
  parameter int KERNEL_SIZE = 3;

  localparam int IMAGE_WIDTH = 64;

  localparam int DUMMY = 4;

  logic clk;
  logic rst_n;

  logic        ker_ready;
  logic        ker_valid;
  logic [31:0] ker_data;

  logic       s_ready;
  logic       s_valid;
  logic       s_last;
  logic [7:0] s_data;

  logic       m_ready;
  logic       m_valid;
  logic [7:0] m_data;

  conv1d #(
    .KERNEL_SIZE(KERNEL_SIZE)
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .ker_valid(ker_valid),
    .ker_data (ker_data),
    .ker_ready(ker_ready),
    .s_valid  (s_valid),
    .s_last   (s_last),
    .s_data   (s_data),
    .s_ready  (s_ready),
    .m_ready  (m_ready),
    .m_valid  (m_valid),
    .m_data   (m_data)
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
    rst_n     = 1'b0;
    ker_valid = 1'b0;
    ker_data  = 32'h3f800000;  // 1.0
    s_valid   = 1'b0;
    s_last    = 1'b0;
    s_data    = '0;
    m_ready   = 1'b1;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    if (KERNEL_SIZE != 3) begin
      $fatal(1, "Invalid parameters: KERNEL_SIZE must be 3");
    end
    reset_dut();

    $display("Test 0: Unloaded kernel");
    for (int cycle = 0; cycle < KERNEL_SIZE + DUMMY; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_data  = cycle[7:0];

      @(posedge clk);
      check_value(s_ready, 0, cycle, "s_ready");
    end

    $display("Test 1: Kernel loading and window sums");
    for (int i = 0; i < KERNEL_SIZE; i++) begin
      @(negedge clk);
      s_valid   = 1'b0;
      ker_valid = 1'b1;

      @(posedge clk);
      check_value(ker_ready, 1'b1, i, "ker_ready");
      check_value(s_ready, 1'b0, i, "s_ready");
    end

    for (int cycle = 0; cycle < IMAGE_WIDTH + DUMMY; cycle++) begin
      @(negedge clk);
      ker_valid = 1'b0;
      s_valid   = 1'b1;
      s_data    = cycle[7:0];

      @(posedge clk);
      check_value(s_ready, 1'b1, cycle, "s_ready");
      check_value(m_valid, (cycle >= KERNEL_SIZE), cycle, "m_valid");
      if (cycle >= KERNEL_SIZE) begin
        check_value(m_data, (cycle - 2) * KERNEL_SIZE, cycle, "m_data");
      end
    end

    reset_dut();

    $display("Test 2: Output backpressure");
    for (int i = 0; i < KERNEL_SIZE; i++) begin
      @(negedge clk);
      s_valid   = 1'b0;
      ker_valid = 1'b1;
      @(posedge clk);
    end

    @(negedge clk);
    ker_valid = 1'b0;
    m_ready   = 1'b0;

    for (int cycle = 0; cycle < KERNEL_SIZE + DUMMY; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_data  = cycle + 1;

      @(posedge clk);
      check_value(s_ready, (cycle < KERNEL_SIZE), cycle, "s_ready");
      check_value(m_valid, (cycle >= KERNEL_SIZE), cycle, "m_valid");
    end

    @(negedge clk);
    m_ready = 1'b1;

    @(posedge clk);
    check_value(s_ready, 1'b1, 0, "s_ready");
    check_value(m_valid, 1'b1, 0, "m_valid");
    check_value(m_data, KERNEL_SIZE * (KERNEL_SIZE + 1) / 2, 0, "m_data");

    @(negedge clk);
    s_valid = 1'b0;
    @(posedge clk);
    check_value(m_data, (KERNEL_SIZE + 1) * KERNEL_SIZE, 1, "m_data");

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
