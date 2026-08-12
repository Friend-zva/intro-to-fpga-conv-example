module weight_loader #(
    parameter integer KERNEL_SIZE = 3
) (
    input logic clk,
    input logic rst_n,

    output logic [KERNEL_SIZE-1:0] row_valid,
    input  logic [KERNEL_SIZE-1:0] row_ready,

    output logic [31:0] data
);
  localparam integer M2 = KERNEL_SIZE * KERNEL_SIZE;

  logic [$clog2(M2)-1:0] addr;
  logic [31:0] out;

  Gowin_ROM u_weights_rom (
      .dout (out),
      .clk  (clk),
      .oce  (1'b1),
      .ce   (1'b1),
      .reset(~rst_n),
      .ad   (addr)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr    <= '0;
      row_valid <= '0;
    end else begin
      row_valid <= '0;

      if (row_ready[addr/KERNEL_SIZE]) begin
        row_valid[addr/KERNEL_SIZE] <= '1;
        data <= out;
        addr <= (addr == M2 - 1) ? '0 : (addr + 1'b1);
      end
    end
  end

endmodule
