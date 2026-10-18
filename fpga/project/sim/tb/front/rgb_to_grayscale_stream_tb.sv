`timescale 1ns / 1ps

module rgb_to_grayscale_stream_tb ();
  parameter integer AXI_DATA_WIDTH = 256;
  parameter integer AXI_ADDR_WIDTH = 29;
  parameter integer AXI_LEN_WIDTH = 20;

  localparam integer COUNT_PIXELS = AXI_DATA_WIDTH / 32;

  logic                      clk;
  logic                      rst_n;

  logic [AXI_ADDR_WIDTH-1:0] cfg_read_addr;
  logic [ AXI_LEN_WIDTH-1:0] cfg_len;

  taxi_dma_desc_if #(
      .SRC_ADDR_W(AXI_ADDR_WIDTH),
      .LEN_W(AXI_LEN_WIDTH)
  ) rd_desc_req ();
  taxi_axis_if #(.DATA_W(AXI_DATA_WIDTH)) s_axis_rx ();

  logic       m_ready;
  logic       m_valid;
  logic       m_last;
  logic [7:0] m_data;

  logic       run;

  rgb_to_grayscale_stream #(
      .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
      .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
      .AXI_LEN_WIDTH (AXI_LEN_WIDTH)
  ) dut (
      .clk(clk),
      .rst_n(rst_n),
      .cfg_read_addr(cfg_read_addr),
      .cfg_len(cfg_len),
      .rd_desc_req(rd_desc_req),
      .s_axis_rx(s_axis_rx),
      .m_ready(m_ready),
      .m_valid(m_valid),
      .m_last(m_last),
      .m_data(m_data),
      .run(run)
  );

  int errors;
  int checks;
  int checked_pixels;
  logic [AXI_DATA_WIDTH-1:0] beat;

  task check_value(input logic [63:0] got, input logic [63:0] exp, input int cycle,
                   input string tag);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL %s [%0d]: got=%0h exp=%0h", tag, cycle, got, exp);
    end
  endtask

  function automatic logic [7:0] expect_gray(input logic [31:0] rgbx);
    int unsigned sum;
    sum = int'(rgbx[7:0]) * 77 + int'(rgbx[15:8]) * 150 + int'(rgbx[23:16]) * 29;
    return 8'(sum / 256);
  endfunction

  // Little-endian RGBX: black, white, red, green, blue, gray, two mixed colors
  function automatic logic [31:0] get_pixel(input int index);
    case (index % 8)
      0: return {8'hA5, 8'd0, 8'd0, 8'd0};
      1: return {8'hA5, 8'd255, 8'd255, 8'd255};
      2: return {8'hA5, 8'd0, 8'd0, 8'd255};
      3: return {8'hA5, 8'd0, 8'd255, 8'd0};
      4: return {8'hA5, 8'd255, 8'd0, 8'd0};
      5: return {8'hA5, 8'd128, 8'd128, 8'd128};
      6: return {8'hA5, 8'd17, 8'd91, 8'd203};
      7: return {8'hA5, 8'd240, 8'd63, 8'd11};
    endcase
  endfunction

  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  task reset_dut();
    @(negedge clk);
    rst_n                 = 1'b0;
    run                   = 1'b0;
    cfg_read_addr         = '0;
    cfg_len               = '0;
    m_ready               = 1'b0;
    rd_desc_req.req_ready = 1'b0;
    s_axis_rx.tvalid      = 1'b0;
    s_axis_rx.tlast       = 1'b0;
    s_axis_rx.tdata       = '0;
    s_axis_rx.tkeep       = '1;
    @(negedge clk);
    rst_n = 1'b1;
  endtask

  initial begin
    if (AXI_DATA_WIDTH < 64 || AXI_DATA_WIDTH % 32 != 0) begin
      $fatal(1, "Invalid parameters: AXI_DATA_WIDTH must be >= 64 and a multiple of 32");
    end
    reset_dut();

    $display("Test 0: Descriptor backpressure");
    @(negedge clk);
    rd_desc_req.req_ready = 1'b1;

    @(negedge clk);
    cfg_read_addr = AXI_ADDR_WIDTH'('h1000);
    cfg_len = AXI_LEN_WIDTH'(2 * (AXI_DATA_WIDTH / 8));
    run = 1'b1;

    repeat (2) @(posedge clk);
    check_value(rd_desc_req.req_valid, 1'b1, int'($time / 10), "rd_desc_req.req_valid");
    check_value(64'(rd_desc_req.req_src_addr), 64'(cfg_read_addr), int'($time / 10),
                "rd_desc_req.req_src_addr");
    check_value(64'(rd_desc_req.req_len), 64'(cfg_len), int'($time / 10), "rd_desc_req.req_len");
    check_value(m_valid, 1'b0, int'($time / 10), "m_valid");
    check_value(s_axis_rx.tready, 1'b0, int'($time / 10), "s_axis_rx.tready");

    repeat (2) @(posedge clk);
    check_value(rd_desc_req.req_valid, 1'b0, int'($time / 10), "rd_desc_req.req_valid");
    check_value(m_valid, 1'b0, int'($time / 10), "m_valid");
    check_value(s_axis_rx.tready, 1'b1, int'($time / 10), "s_axis_rx.tready");


    for (int beat = 0; beat < 2; beat++) begin
      $display("Test %0d: AXI input beat", beat + 1);
      @(negedge clk);
      for (int i = 0; i < COUNT_PIXELS; i++) begin
        beat[i*32+:32] = get_pixel(beat * 5 + i);
      end
      s_axis_rx.tdata = beat;
      s_axis_rx.tvalid = 1'b1;
      s_axis_rx.tlast = (beat == 1);
      m_ready = 1'b0;

      @(posedge clk);
      check_value(s_axis_rx.tready, 1'b1, int'($time / 10), "s_axis_rx.tready");
      check_value(m_valid, 1'b0, int'($time / 10), "m_valid");

      @(posedge clk);
      check_value(s_axis_rx.tready, 1'b0, int'($time / 10), "s_axis_rx.tready");

      @(negedge clk);
      s_axis_rx.tvalid = 1'b0;
      s_axis_rx.tlast  = 1'b0;

      @(negedge clk);
      m_ready = 1'b1;
      @(posedge clk);

      for (int i = 0; i < COUNT_PIXELS; i++) begin
        @(posedge clk);
        check_value(m_valid, 1'b1, int'($time / 10), "m_valid");
        check_value(64'(m_data), 64'(expect_gray(beat[i*32+:32])), int'($time / 10), "m_data");
        check_value(m_last, beat == 1 && i == COUNT_PIXELS - 1, int'($time / 10), "m_last");
        checked_pixels++;
      end

      @(posedge clk);
      check_value(m_valid, 1'b0, int'($time / 10), "m_valid");
      check_value(s_axis_rx.tready, beat == 0, int'($time / 10), "s_axis_rx.tready");
    end

    if (errors == 0) begin
      $display("PASS: %0d checks", checks);
    end else begin
      $fatal(1, "FAIL: %0d of %0d checks", errors, checks);
    end
    $finish;
  end

endmodule
