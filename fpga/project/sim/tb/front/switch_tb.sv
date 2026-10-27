`timescale 1ns / 1ps

module switch_tb ();
  parameter int M = 3;
  parameter int RD_LATENCY = 2;

  localparam int N = M + 1;
  localparam int IMAGE_WIDTH = 4;
  localparam int IMAGE_HEIGHT = 6;

  localparam int DUMMY = 3;

  logic clk;
  logic rst_n;

  logic [$clog2(N)-1:0] write_sel;
  logic [          M:0] line_valid;

  logic       s_valid;
  logic       s_last;
  logic [7:0] s_data  [N];
  logic       s_ready;

  logic       m_ready;
  logic       m_valid;
  logic       m_last;
  logic [7:0] m_data  [M];

  switch #(
    .M         (M),
    .RD_LATENCY(RD_LATENCY)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .write_sel (write_sel),
    .line_valid(line_valid),
    .s_valid   (s_valid),
    .s_last    (s_last),
    .s_data    (s_data),
    .s_ready   (s_ready),
    .m_ready   (m_ready),
    .m_valid   (m_valid),
    .m_last    (m_last),
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
    rst_n      = 1'b0;
    write_sel  = '0;
    line_valid = '0;
    s_valid    = 1'b0;
    s_last     = 1'b0;
    for (int i = 0; i < N; i++) s_data[i] = '0;
    m_ready = 1'b1;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  logic                  exp_valid;
  logic [RD_LATENCY-1:0] exp_valid_pipe;

  initial begin
    if (M < 1 || IMAGE_WIDTH < 2 || RD_LATENCY < 1) begin
      $fatal(1, "Invalid parameters: M >= 1, IMAGE_WIDTH >= 2, RD_LATENCY >= 1");
    end
    reset_dut();

    $display("Test 1: Line selection and output data");
    for (int sel = 0; sel < N; sel++) begin
      @(negedge clk);
      s_valid = 1'b1;
      for (int i = 0; i < N; i++) s_data[i] = i;
      line_valid        = '1;
      write_sel         = sel;
      s_data[write_sel] = 8'hFF;

      @(posedge clk);
      for (int out = 0; out < M; out++) begin
        check_value(m_data[out], s_data[(write_sel+out+1)%N], sel, "m_data");
      end
    end

    reset_dut();

    $display("Test 2: Line selection and output validity");
    exp_valid_pipe = '0;

    for (int cycle = 0; cycle < IMAGE_WIDTH * IMAGE_HEIGHT; cycle++) begin
      @(negedge clk);
      s_valid = (cycle < IMAGE_WIDTH * IMAGE_HEIGHT - RD_LATENCY);
      if (cycle % IMAGE_WIDTH == RD_LATENCY) begin
        write_sel = (write_sel == M) ? '0 : write_sel + 1;
      end

      for (int i = 0; i < N; i++) begin
        if (cycle == (i + 1) * IMAGE_WIDTH + RD_LATENCY) begin
          line_valid[i] = 1'b1;
        end
      end

      @(posedge clk);
      exp_valid = exp_valid_pipe[RD_LATENCY-1];
      for (int j = 0; j < N; j++) begin
        if (j != write_sel) exp_valid &= line_valid[j];
      end
      check_value(m_valid, exp_valid, cycle, "m_valid");

      exp_valid_pipe = (exp_valid_pipe << 1) | s_valid;
    end

    reset_dut();

    $display("Test 3: Final output marker");
    for (int cycle = 0; cycle < IMAGE_WIDTH + RD_LATENCY + DUMMY; cycle++) begin
      @(negedge clk);
      s_valid = (cycle < IMAGE_WIDTH - RD_LATENCY);
      s_last  = (cycle == IMAGE_WIDTH - 1);

      @(posedge clk);
      check_value(m_last, ((cycle - RD_LATENCY) == IMAGE_WIDTH - 1), cycle,
                  "m_last");
      check_value(s_ready, 1'b1, cycle, "s_ready");
    end

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
