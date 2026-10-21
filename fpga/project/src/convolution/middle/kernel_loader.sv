module kernel_loader #(
    parameter integer KERNEL_SIZE = 3,
    parameter integer RD_LATENCY  = 2
) (
    input logic clk,
    input logic rst_n,

    input  logic [KERNEL_SIZE-1:0] row_ready,
    output logic [KERNEL_SIZE-1:0] row_valid,

    output logic [31:0] data
);
  localparam integer M2 = KERNEL_SIZE * KERNEL_SIZE;

  if (RD_LATENCY < 1) begin : fatal_latency
    $fatal(0, "Error: RD_LATENCY must be more than 0");
  end

  logic [         $clog2(M2)-1:0] addr;

  logic                           req_valid_pipe[RD_LATENCY];
  logic [$clog2(KERNEL_SIZE)-1:0] req_row_pipe  [RD_LATENCY];

  Gowin_ROM u_kernel (
      .dout (data),
      .clk  (clk),
      .oce  (1'b1),
      .ce   (1'b1),
      .reset(~rst_n),
      .ad   (addr)
  );

  wire req_fire = row_ready[addr/KERNEL_SIZE];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr <= '0;
      for (int i = 0; i < RD_LATENCY; i++) begin
        req_valid_pipe[i] <= 1'b0;
        req_row_pipe[i]   <= '0;
      end
    end else begin
      req_valid_pipe[0] <= req_fire;
      req_row_pipe[0]   <= addr / KERNEL_SIZE;
      for (int i = 1; i < RD_LATENCY; i++) begin
        req_valid_pipe[i] <= req_valid_pipe[i-1];
        req_row_pipe[i]   <= req_row_pipe[i-1];
      end

      if (req_fire) begin
        addr <= (addr == M2 - 1) ? '0 : (addr + 1'b1);
      end
    end
  end

  always_comb begin
    row_valid = '0;
    if (req_valid_pipe[RD_LATENCY-1]) begin
      row_valid[req_row_pipe[RD_LATENCY-1]] = 1'b1;
    end
  end

endmodule
