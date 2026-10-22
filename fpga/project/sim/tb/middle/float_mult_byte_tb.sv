`timescale 1ns / 1ps

module float_mult_byte_tb ();
  localparam int FLOAT_COUNT = 6;
  localparam int BYTE_COUNT = 3;

  logic [31:0] float_in;
  logic [ 7:0] uint8_in;
  logic [ 7:0] uint8_out;

  float_mult_byte dut (
    .float_in (float_in),
    .uint8_in (uint8_in),
    .uint8_out(uint8_out)
  );

  int errors;
  int checks;

  task check_value(input logic [7:0] got, input logic [7:0] exp, input int test);
    checks++;
    if (got !== exp) begin
      errors++;
      $display("FAIL [%0d]: got=%0d exp=%0d", test, got, exp);
    end
  endtask

  function logic [31:0] float_value(input int index);
    case (index)
      0: return 32'h4148_0000;  // 12.5
      1: return 32'h4189_999a;  // 17.2
      2: return 32'h4348_0000;  // 200
      3: return 32'h3e7e_0000;  // 0.248
      4: return 32'h3ea8_f5c3;  // 0.33
      5: return 32'h3f7f_ffde;  // 0.999999
    endcase
  endfunction

  function logic [7:0] byte_value(input int index);
    case (index)
      0: return 8'd2;
      1: return 8'd10;
      2: return 8'd15;
    endcase
  endfunction

  function logic [7:0] expect_value(input int float_index, input int byte_index);
    case (float_index)
      0: return (byte_index == 0) ? 8'd25 : (byte_index == 1) ? 8'd125 : 8'd187;
      1: return (byte_index == 0) ? 8'd34 : (byte_index == 1) ? 8'd172 : 8'd255;
      2: return 8'd255;
      3: return (byte_index == 0) ? 8'd0 : (byte_index == 1) ? 8'd2 : 8'd3;
      4: return (byte_index == 0) ? 8'd0 : (byte_index == 1) ? 8'd3 : 8'd4;
      5: return (byte_index == 0) ? 8'd1 : (byte_index == 1) ? 8'd9 : 8'd14;
    endcase
  endfunction


  initial begin
    for (int i = 0; i < FLOAT_COUNT; i++) begin
      for (int j = 0; j < BYTE_COUNT; j++) begin
        float_in = float_value(i);
        uint8_in = byte_value(j);

        #1;
        check_value(uint8_out, expect_value(i, j), i * BYTE_COUNT + j);
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
