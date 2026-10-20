`timescale 1ns / 1ps

`ifndef ROM_LAT
`define ROM_LAT 2
`endif

module Gowin_ROM (
    output logic [31:0] dout,
    input  logic        clk,
    input  logic        oce,
    input  logic        ce,
    input  logic        reset,
    input  logic [ 3:0] ad
);
  localparam integer LATENCY = `ROM_LAT;
  localparam integer DEPTH = 9;

  logic [31:0] mem [  DEPTH];
  logic [31:0] pipe[LATENCY];

  initial begin
    mem[0] = 32'h3E000000;
    mem[1] = 32'h3D800000;
    mem[2] = 32'h3E000000;
    mem[3] = 32'h3E800000;
    mem[4] = 32'h3E000000;
    mem[5] = 32'h3D800000;
    mem[6] = 32'h3E000000;
    mem[7] = 32'h3D800000;
    mem[8] = 32'h3D800000;
  end

  always @(posedge clk) begin
    if (reset) begin
      for (int i = 0; i < LATENCY; i++) pipe[i] <= '0;
    end else begin
      if (ce) pipe[0] <= mem[ad];
      for (int i = 1; i < LATENCY; i++) begin
        if (oce) pipe[i] <= pipe[i-1];
      end
    end
  end

  assign dout = pipe[LATENCY-1];

endmodule
