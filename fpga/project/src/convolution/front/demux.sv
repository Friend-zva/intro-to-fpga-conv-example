module demux_1_to_m1 #(
    parameter integer IMAGE_WIDTH = 640,
    parameter integer M           = 3,
    parameter integer RD_LATENCY  = 2
) (
    input logic clk,
    input logic rst_n,

    input  logic       s_valid,
    input  logic       s_last,
    input  logic [7:0] s_data,
    output logic       s_ready,

    input  logic       m_ready,
    output logic       m_valid,
    output logic [7:0] m_data,

    output logic [            M:0] write_en,
    output logic [$clog2(M+1)-1:0] write_sel,

    output logic [$clog2(IMAGE_WIDTH)-1:0] addr
);
  localparam integer SEL_W = $clog2(M + 1);

  logic [                  SEL_W-1:0] write_sel_raw;
  wire                                s_fire = s_valid && s_ready;

  logic                               last_run;
  logic                               last_done;
  logic [$clog2(IMAGE_WIDTH + 1)-1:0] last_cnt;
  wire                                last_fire = last_run && m_ready;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      addr          <= '0;
      write_sel_raw <= '0;
    end else begin
      if (s_fire || last_fire) begin
        if (addr == IMAGE_WIDTH - 1) begin
          addr <= '0;
        end else begin
          addr <= addr + 1;
        end
      end

      if (s_fire && addr == IMAGE_WIDTH - 1) begin
        write_sel_raw <= (write_sel_raw == M[SEL_W-1:0]) ? '0 : write_sel_raw + 1;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      last_run  <= 1'b0;
      last_done <= 1'b0;
      last_cnt  <= '0;
    end else if (s_fire && s_last) begin
      last_run <= 1'b1;
      last_cnt <= '0;
    end else if (last_fire) begin
      if (last_cnt == IMAGE_WIDTH - 1) begin
        last_run  <= 1'b0;
        last_done <= 1'b1;
      end else begin
        last_cnt <= last_cnt + 1;
      end
    end
  end

  assign s_ready = m_ready && !last_run && !last_done;
  assign m_valid = s_fire || last_fire;
  assign m_data  = s_data;

  always_comb begin
    write_en = '0;
    if (s_fire) begin
      write_en[write_sel_raw] = 1'b1;
    end
  end

  logic [SEL_W-1:0] write_sel_pipe[RD_LATENCY];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < RD_LATENCY; i++) begin
        write_sel_pipe[i] <= '0;
      end
    end else begin
      write_sel_pipe[0] <= write_sel_raw;
      for (int i = 1; i < RD_LATENCY; i++) begin
        write_sel_pipe[i] <= write_sel_pipe[i-1];
      end
    end
  end

  assign write_sel = write_sel_pipe[RD_LATENCY-1];

endmodule
