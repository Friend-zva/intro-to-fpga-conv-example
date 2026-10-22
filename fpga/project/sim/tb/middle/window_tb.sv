`timescale 1ns / 1ps

module window_tb ();
  parameter int WINDOW_SIZE = 3;

  localparam int IMAGE_WIDTH = 64;

  logic clk;
  logic rst_n;
  logic run;

  logic       s_valid;
  logic       s_last;
  logic [7:0] s_data;

  logic       m_ready;
  logic       m_valid;
  logic [7:0] m_data  [WINDOW_SIZE];

  window #(
    .WINDOW_SIZE(WINDOW_SIZE)
  ) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .run    (run),
    .s_valid(s_valid),
    .s_last (s_last),
    .s_data (s_data),
    .m_ready(m_ready),
    .m_valid(m_valid),
    .m_data (m_data)
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
    run     = 1'b0;
    s_valid = 1'b0;
    s_last  = 1'b0;
    s_data  = '0;
    m_ready = 1'b1;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    reset_dut();

    $display("Test 0: Disabled window");
    for (int cycle = 0; cycle < IMAGE_WIDTH; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_data  = cycle[7:0];

      @(posedge clk);
      check_value(m_valid, 1'b0, cycle, "m_valid");
    end

    $display("Test 1: Window fill");
    for (int cycle = 0; cycle < IMAGE_WIDTH; cycle++) begin
      @(negedge clk);
      run     = 1'b1;
      s_valid = 1'b1;
      s_data  = cycle[7:0];

      @(posedge clk);
      check_value(m_valid, (cycle >= WINDOW_SIZE), cycle, "m_valid");
      if (m_valid) begin
        for (int i = 0; i < WINDOW_SIZE; i++) begin
          check_value(m_data[i], cycle - WINDOW_SIZE + i, cycle, "m_data");
        end
      end
    end

    $display("Test 2: Window flush");
    @(negedge clk);
    s_valid = 1'b1;
    s_last  = 1'b1;
    s_data  = 8'hFF;

    @(posedge clk);
    check_value(m_valid, 1'b1, 0, "m_valid");

    @(negedge clk);
    s_valid = 1'b0;
    s_last  = 1'b0;

    @(posedge clk);
    check_value(m_valid, 1'b1, 1, "m_valid");
    @(posedge clk);
    check_value(m_valid, 1'b0, 2, "m_valid");

    $display("Test 3: Window refill");
    for (int cycle = 0; cycle < IMAGE_WIDTH; cycle++) begin
      @(negedge clk);
      run     = 1'b1;
      s_valid = 1'b1;
      s_data  = cycle[7:0];

      @(posedge clk);
      check_value(m_valid, (cycle >= WINDOW_SIZE), cycle, "m_valid");
    end

    $display("Test 4: Immediate window refill");
    @(negedge clk);
    s_valid = 1'b1;
    s_last  = 1'b1;
    s_data  = IMAGE_WIDTH;
    @(posedge clk);
    check_value(m_valid, 1'b1, 0, "m_valid");

    for (int cycle = 0; cycle < IMAGE_WIDTH; cycle++) begin
      @(negedge clk);
      run     = 1'b1;
      s_valid = 1'b1;
      s_last  = 1'b0;
      s_data  = cycle[7:0] + 1;

      @(posedge clk);
      check_value(m_valid, (cycle == 0 || cycle >= WINDOW_SIZE), cycle, "m_valid");
      if (cycle == 0) begin
        for (int i = 0; i < WINDOW_SIZE; i++) begin
          check_value(m_data[i], IMAGE_WIDTH - WINDOW_SIZE + 1 + i, cycle, "m_data");
        end
      end
    end

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
