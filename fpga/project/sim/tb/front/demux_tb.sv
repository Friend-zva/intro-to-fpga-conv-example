`timescale 1ns / 1ps

module demux_tb ();
  parameter integer M = 3;
  parameter integer IMAGE_WIDTH = 8;
  parameter integer RD_LATENCY = 2;

  localparam integer N = M + 1;
  localparam integer SEL_W = $clog2(N);
  localparam integer ADDR_W = $clog2(IMAGE_WIDTH);

  localparam integer DUMMY = 3;

  logic              clk;
  logic              rst_n;

  logic              s_valid;
  logic              s_last;
  logic [       7:0] s_data;
  logic              s_ready;

  logic              m_ready;
  logic              m_valid;
  logic              m_last;
  logic [       7:0] m_data;

  logic [       M:0] write_en;
  logic [ SEL_W-1:0] write_sel;

  logic [ADDR_W-1:0] addr;

  demux_1_to_m1 #(
      .M(M),
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .RD_LATENCY(RD_LATENCY)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(s_valid),
      .s_last(s_last),
      .s_data(s_data),
      .s_ready(s_ready),
      .m_ready(m_ready),
      .m_valid(m_valid),
      .m_last(m_last),
      .m_data(m_data),
      .write_en(write_en),
      .write_sel(write_sel),
      .addr(addr)
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

  logic [ADDR_W-1:0] exp_addr;
  logic [       M:0] exp_write_en;
  logic [ SEL_W-1:0] exp_write_sel;

  initial begin
    if (M < 1 || IMAGE_WIDTH < 2 || RD_LATENCY < 1) begin
      $fatal(1, "Invalid parameters: M >= 1, IMAGE_WIDTH >= 2, RD_LATENCY >= 1");
    end
    reset_dut();

    $display("Test 1: Address calculation");
    for (int cycle = 0; cycle < IMAGE_WIDTH + DUMMY; cycle++) begin
      @(negedge clk);
      s_valid  = (cycle < IMAGE_WIDTH);
      exp_addr = (cycle < IMAGE_WIDTH) ? cycle : '0;

      @(posedge clk);
      check_value(m_valid, s_valid, cycle, "m_valid");
      check_value(m_last, (exp_addr == IMAGE_WIDTH - 1), cycle, "m_last");
      check_value(addr, exp_addr, cycle, "addr");
    end

    $display("Test 2: Final line validity");
    for (int cycle = 0; cycle < IMAGE_WIDTH; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_last  = (cycle == IMAGE_WIDTH - 1);

      @(posedge clk);
      check_value(addr, cycle[ADDR_W-1:0], cycle, "addr");
    end
    for (int cycle = 0; cycle < IMAGE_WIDTH + DUMMY; cycle++) begin
      @(negedge clk);
      s_valid  = 1'b0;
      s_last   = 1'b0;
      exp_addr = (cycle < IMAGE_WIDTH) ? cycle : '0;

      @(posedge clk);
      check_value(s_ready, 1'b0, cycle, "s_ready");
      check_value(m_valid, cycle < IMAGE_WIDTH, cycle, "m_valid");
      check_value(m_last, (exp_addr == IMAGE_WIDTH - 1), cycle, "m_last");
      check_value(addr, exp_addr, cycle, "addr");
    end

    reset_dut();

    $display("Test 3: Write enable and selector latency");
    for (int cycle = 0; cycle < 3 * IMAGE_WIDTH; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      exp_write_en = '0;
      exp_write_en[(cycle/IMAGE_WIDTH)%N] = 1'b1;
      exp_write_sel = (cycle < RD_LATENCY) ? 0 : ((cycle - RD_LATENCY) / IMAGE_WIDTH) % N;

      @(posedge clk);
      check_value(write_en, exp_write_en, cycle, "write_en");
      check_value(write_sel, exp_write_sel, cycle, "write_sel");
    end

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
