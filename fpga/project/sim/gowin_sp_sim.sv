`timescale 1ns / 1ps

`ifndef SP_LAT
`define SP_LAT 2
`endif

module Gowin_SP (
    output logic [7:0] dout,
    input  logic       clk,
    input  logic       oce,
    input  logic       ce,
    input  logic       reset,
    input  logic       wre,
    input  logic [9:0] ad,
    input  logic [7:0] din
);
  localparam integer LATENCY = `SP_LAT;
  localparam integer DEPTH = 64;

  logic [7:0] mem [  DEPTH];
  logic [7:0] pipe[LATENCY];

  initial begin
    for (int i = 0; i < DEPTH; i++) mem[i] = 8'h00;
  end

  always @(posedge clk) begin
    if (!reset && ce && wre) mem[ad] <= din;
  end

  always @(posedge clk or posedge reset) begin
    if (reset) begin
      for (int i = 0; i < LATENCY; i++) pipe[i] <= 8'h00;
    end else if (ce) begin
      if (!wre) pipe[0] <= mem[ad];
      for (int i = 1; i < LATENCY; i++) begin
        if (oce) pipe[i] <= pipe[i-1];
      end
    end
  end

  assign dout = pipe[LATENCY-1];

endmodule
