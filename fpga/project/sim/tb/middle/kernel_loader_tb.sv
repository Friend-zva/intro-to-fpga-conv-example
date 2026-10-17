`timescale 1ns / 1ps

module kernel_loader_tb ();
  parameter integer KERNEL_SIZE = 3;
  parameter integer RD_LATENCY = 2;

  localparam integer M2 = KERNEL_SIZE * KERNEL_SIZE;

  localparam integer DUMMY = 2;

  logic                   clk;
  logic                   rst_n;

  logic [KERNEL_SIZE-1:0] row_ready;
  logic [KERNEL_SIZE-1:0] row_valid;

  logic [           31:0] data;

  kernel_loader #(
      .KERNEL_SIZE(KERNEL_SIZE),
      .RD_LATENCY (RD_LATENCY)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .row_ready(row_ready),
      .row_valid(row_valid),
      .data(data)
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

  int                     row_abs;
  logic [KERNEL_SIZE-1:0] exp_valid;
  logic [           31:0] exp_data        [M2];
  int                     exp_index;
  int                     exp_weights_cnt;

  task reset_dut();
    @(negedge clk);
    rst_n     = 1'b0;
    row_ready = '0;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    if (KERNEL_SIZE != 3 || RD_LATENCY < 1) begin
      $fatal(1, "Invalid parameters: KERNEL_SIZE must be 3, RD_LATENCY must be >= 1");
    end
    reset_dut();

    exp_data[0] = 32'h3E000000;
    exp_data[1] = 32'h3D800000;
    exp_data[2] = 32'h3E000000;
    exp_data[3] = 32'h3E800000;
    exp_data[4] = 32'h3E000000;
    exp_data[5] = 32'h3D800000;
    exp_data[6] = 32'h3E000000;
    exp_data[7] = 32'h3D800000;
    exp_data[8] = 32'h3D800000;

    $display("Test 1: ROM latency and row stream");
    for (int row = 0; row < KERNEL_SIZE; row++) begin
      for (int cycle = 0; cycle < KERNEL_SIZE + RD_LATENCY + DUMMY; cycle++) begin
        @(negedge clk);
        row_ready = '0;
        if (cycle < KERNEL_SIZE) row_ready[row] = 1'b1;

        exp_valid = '0;
        if (cycle >= RD_LATENCY && cycle < RD_LATENCY + KERNEL_SIZE) begin
          exp_valid[row] = 1'b1;
        end

        @(posedge clk);
        for (int j = 0; j < KERNEL_SIZE; j++) begin
          check_value(row_valid[j], exp_valid[j], cycle, "row_valid");
        end
        if (exp_valid[row]) begin
          exp_index = row * KERNEL_SIZE + cycle - RD_LATENCY;
          check_value(data, exp_data[exp_index], cycle, "data");
          exp_weights_cnt++;
        end
      end
    end

    check_value(exp_weights_cnt, M2, 0, "exp_weights_cnt");

    @(negedge clk);
    rst_n = 1'b1;

    $display("Test 2: Out-of-row addresses");
    for (int _row = -2; _row < KERNEL_SIZE; _row++) begin
      row_abs = (_row < 0) ? -_row : _row;
      for (int cycle = 0; cycle < KERNEL_SIZE + RD_LATENCY + DUMMY; cycle++) begin
        @(negedge clk);
        row_ready = '0;
        if (cycle < KERNEL_SIZE) row_ready[row_abs] = 1'b1;

        exp_valid = '0;
        if (_row >= 0 && cycle >= RD_LATENCY && cycle < RD_LATENCY + KERNEL_SIZE) begin
          exp_valid[row_abs] = 1'b1;
        end

        @(posedge clk);
        for (int j = 0; j < KERNEL_SIZE; j++) begin
          check_value(row_valid[j], exp_valid[j], cycle, "row_valid");
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
