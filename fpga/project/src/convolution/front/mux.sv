module mux_m1_to_m #(
    parameter integer M = 3
) (
    input  logic [$clog2(M+1)-1:0] write_sel,
    input  logic [            7:0] rx_data  [M+1],
    output logic [            7:0] tx_data  [  M]
);
  localparam integer N = M + 1;

  always_comb begin
    for (int i = 0; i < M; i++) begin
      tx_data[i] = rx_data[(write_sel+1+i)%N];
    end
  end

endmodule
