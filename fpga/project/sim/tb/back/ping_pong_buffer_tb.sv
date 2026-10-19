`timescale 1ns / 1ps

module ping_pong_buffer_tb ();
  parameter integer IMAGE_WIDTH = 62;
  parameter integer RD_LATENCY = 2;

  localparam integer IMAGE_WIDTH_FULL = IMAGE_WIDTH + 2;

  logic                           clk;
  logic                           rst_n;

  logic                           s_valid;
  logic [                    7:0] s_data;
  logic                           s_ready;

  logic                           m_valid;
  logic [                    7:0] m_data;

  logic                           rd_req;
  logic                           rd_sel;
  logic [$clog2(IMAGE_WIDTH)-1:0] rd_addr;

  logic                           done_ready;
  logic                           done;
  logic                           done_sel;

  ping_pong_buffer #(
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .RD_LATENCY (RD_LATENCY)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .s_valid(s_valid),
      .s_data(s_data),
      .s_ready(s_ready),
      .m_valid(m_valid),
      .m_data(m_data),
      .rd_req(rd_req),
      .rd_sel(rd_sel),
      .rd_addr(rd_addr),
      .done_ready(done_ready),
      .done(done),
      .done_sel(done_sel)
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
    s_valid    = 1'b0;
    s_data     = '0;
    rd_req     = 1'b0;
    rd_sel     = 1'b0;
    rd_addr    = '0;
    done_ready = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  logic exp_valid;

  initial begin
    if (IMAGE_WIDTH < 2 || IMAGE_WIDTH > 64 || RD_LATENCY < 1) begin
      $fatal(
          1,
          "Invalid parameters: IMAGE_WIDTH between 2 and 64, RD_LATENCY >= 1; SP_LAT == RD_LATENCY");
    end
    reset_dut();

    $display("Test 1: Buffer A fill");
    for (int cycle = 0; cycle < IMAGE_WIDTH_FULL; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_data  = cycle[7:0];

      @(posedge clk);
      check_value(s_ready, (cycle < IMAGE_WIDTH), cycle, "s_ready");
      check_value(done, (cycle >= IMAGE_WIDTH), cycle, "done");
      check_value(done_sel, 1'b0, cycle, "done_sel");
    end

    $display("Test 2: Bank switch");
    @(negedge clk);
    s_valid = 1'b0;
    done_ready = 1'b1;
    @(posedge clk);
    check_value(done, 1'b1, 0, "done");
    check_value(s_ready, 1'b0, 0, "s_ready");

    @(negedge clk);
    done_ready = 1'b0;
    @(posedge clk);
    check_value(done, 1'b0, 1, "done");
    check_value(s_ready, 1'b1, 1, "s_ready");

    $display("Test 3: Buffer A read");
    for (int cycle = 0; cycle < IMAGE_WIDTH + RD_LATENCY; cycle++) begin
      @(negedge clk);
      rd_req = (cycle < IMAGE_WIDTH);
      rd_sel = 1'b0;
      rd_addr = (cycle < IMAGE_WIDTH) ? cycle : 0;
      exp_valid = (cycle >= RD_LATENCY) && (cycle < RD_LATENCY + IMAGE_WIDTH);

      @(posedge clk);
      check_value(m_valid, exp_valid, cycle, "m_valid");
      check_value(m_data, exp_valid ? cycle - RD_LATENCY : 8'b0, cycle, "m_data");
    end

    $display("Test 4: Buffer B fill");
    for (int cycle = 0; cycle < IMAGE_WIDTH_FULL; cycle++) begin
      @(negedge clk);
      s_valid = 1'b1;
      s_data  = ~cycle[7:0];

      @(posedge clk);
      check_value(s_ready, (cycle < IMAGE_WIDTH), cycle, "s_ready");
      check_value(done, (cycle >= IMAGE_WIDTH), cycle, "done");
      check_value(done_sel, (cycle >= IMAGE_WIDTH), cycle, "done_sel");
    end

    $display("Test 5: Bank switch and buffer A fill blockage");
    @(negedge clk);
    s_valid = 1'b0;
    done_ready = 1'b0;

    @(posedge clk);
    check_value(done, 1'b1, 0, "done");
    check_value(s_ready, 1'b0, 0, "s_ready");

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
