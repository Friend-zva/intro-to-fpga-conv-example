`timescale 1ns / 1ps

module tb_line_buffer ();
  parameter integer IMAGE_WIDTH = 64;
  parameter integer RD_LATENCY = 2;

  localparam integer ADDR_W = $clog2(IMAGE_WIDTH);

  logic              clk;
  logic              rst_n;

  logic [ADDR_W-1:0] addr;

  logic [       7:0] rx_data;
  logic [       7:0] tx_data;

  logic              write_en;
  logic              line_valid;

  line_buffer #(
      .IMAGE_WIDTH(IMAGE_WIDTH),
      .RD_LATENCY (RD_LATENCY)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .addr(addr),
      .rx_data(rx_data),
      .tx_data(tx_data),
      .write_en(write_en),
      .line_valid(line_valid)
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
    rst_n    = 1'b0;
    addr     = '0;
    rx_data  = '0;
    write_en = 1'b0;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    if (IMAGE_WIDTH < 2 || IMAGE_WIDTH > 64 || RD_LATENCY < 1) begin
      $fatal(1, "Invalid parameters: IMAGE_WIDTH between 2 and 64, RD_LATENCY >= 1");
    end
    reset_dut();

    $display("Test 1: Line validity latency");
    for (int i = -2; i <= RD_LATENCY + 2; i++) begin
      @(negedge clk);

      addr     = (i < 0) ? (IMAGE_WIDTH + i) : i;
      write_en = 1'b1;
      rx_data  = i + 2;

      @(posedge clk);
      check_value(line_valid, i >= RD_LATENCY, i + 2, "line_valid");
    end

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
