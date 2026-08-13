module grayscale_to_ddr3_stream #(
    parameter integer AXI_DATA_WIDTH = 256,
    parameter integer AXI_ADDR_WIDTH = 29,
    parameter integer AXI_LEN_WIDTH  = 20,
    parameter integer AXI_STRB_WIDTH = 32,
    parameter integer KERNEL_SIZE    = 3,
    parameter integer IMAGE_WIDTH    = 640,
    parameter integer IMAGE_HEIGHT   = 480
) (
    input logic clk,
    input logic rst_n,

    input logic [AXI_ADDR_WIDTH-1:0] cfg_write_addr,

    taxi_dma_desc_if.req_src wr_desc_req,
    taxi_axis_if.src m_axis_tx,

    output logic                                             rd_req,
    output logic                                             rd_buf_sel,
    output logic [$clog2(IMAGE_WIDTH-2*(KERNEL_SIZE/2))-1:0] rd_addr,

    input logic       s_valid,
    input logic [7:0] s_data,

    input  logic buf_done,
    output logic buf_done_ready,
    input  logic buf_done_sel
);

  localparam integer PAD = KERNEL_SIZE / 2;
  localparam integer ROW_LEN = IMAGE_WIDTH - 2 * PAD;
  localparam integer BYTES_PER_WORD = AXI_DATA_WIDTH / 8;
  localparam integer BEATS_PER_ROW = (ROW_LEN + BYTES_PER_WORD - 1) / BYTES_PER_WORD;
  localparam integer LAST_BEAT_BYTES = ROW_LEN - (BEATS_PER_ROW - 1) * BYTES_PER_WORD;

  logic [ $clog2(BYTES_PER_WORD)-1:0] byte_cnt;
  logic [$clog2(BEATS_PER_ROW+1)-1:0] beat_cnt;
  logic [   $clog2(IMAGE_HEIGHT)-1:0] row_idx;
  logic [         AXI_DATA_WIDTH-1:0] beat_data;

  typedef enum logic [1:0] {
    IDLE,
    DESC,
    PACK,
    SEND
  } state_t;
  state_t state;

  assign buf_done_ready = (state == IDLE);
  assign rd_req = (state == PACK) && !s_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= IDLE;
      byte_cnt <= '0;
      beat_cnt <= '0;
      row_idx <= '0;
      rd_addr <= '0;

      wr_desc_req.req_valid <= 1'b0;
      m_axis_tx.tvalid <= 1'b0;
      m_axis_tx.tlast <= 1'b0;

      rd_buf_sel <= 1'b0;
      beat_data <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (buf_done) begin
            rd_buf_sel               <= buf_done_sel;
            byte_cnt                 <= '0;
            beat_cnt                 <= '0;
            beat_data                <= '0;
            wr_desc_req.req_dst_addr <= cfg_write_addr + (row_idx + PAD) * IMAGE_WIDTH + PAD;
            wr_desc_req.req_len      <= ROW_LEN[AXI_LEN_WIDTH-1:0];
            wr_desc_req.req_valid    <= 1'b1;
            row_idx                  <= row_idx + 1'b1;
            state                    <= DESC;
          end
        end

        DESC: begin
          if (wr_desc_req.req_valid && wr_desc_req.req_ready) begin
            wr_desc_req.req_valid <= 1'b0;
            rd_addr <= '0;
            state <= PACK;
          end
        end

        PACK: begin
          if (s_valid) begin
            beat_data[byte_cnt*8+:8] <= s_data;

            if (byte_cnt == BYTES_PER_WORD - 1 || rd_addr == ROW_LEN - 1) begin
              byte_cnt <= '0;
              state    <= SEND;
            end else begin
              byte_cnt <= byte_cnt + 1'b1;
              rd_addr  <= rd_addr + 1'b1;
            end
          end
        end

        SEND: begin
          m_axis_tx.tvalid <= 1'b1;
          m_axis_tx.tdata  <= beat_data;
          m_axis_tx.tlast  <= (beat_cnt == BEATS_PER_ROW - 1);

          if (m_axis_tx.tvalid && m_axis_tx.tready) begin
            m_axis_tx.tvalid <= 1'b0;

            if (beat_cnt == BEATS_PER_ROW - 1) begin
              state <= IDLE;
            end else begin
              beat_cnt  <= beat_cnt + 1'b1;
              beat_data <= '0;
              rd_addr   <= rd_addr + 1'b1;
              state     <= PACK;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  logic [AXI_STRB_WIDTH-1:0] tkeep_last;
  always_comb begin
    tkeep_last = '0;
    for (int k = 0; k < LAST_BEAT_BYTES; k++) begin
      tkeep_last[k] = 1'b1;
    end
  end

  assign m_axis_tx.tkeep = (beat_cnt == BEATS_PER_ROW - 1) ? tkeep_last : '1;

endmodule
