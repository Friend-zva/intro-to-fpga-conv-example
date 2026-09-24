module rgb_to_grayscale_stream #(
    parameter integer AXI_DATA_WIDTH = 256,
    parameter integer AXI_ADDR_WIDTH = 29,
    parameter integer AXI_LEN_WIDTH  = 20
) (
    input clk,
    input rst_n,

    input [AXI_ADDR_WIDTH-1:0] cfg_read_addr,
    input [ AXI_LEN_WIDTH-1:0] cfg_len,

    taxi_dma_desc_if.req_src rd_desc_req,
    taxi_axis_if.snk s_axis_rx,

    input              m_ready,
    output logic       m_valid,
    output logic       m_last,
    output logic [7:0] m_data,

    input run
);

  assign rd_desc_req.req_src_addr = cfg_read_addr;
  assign rd_desc_req.req_len      = cfg_len;

  localparam integer COUNT_PIXELS = AXI_DATA_WIDTH / 32;
  localparam integer WIDTH_PTR = $clog2(COUNT_PIXELS);
  localparam [WIDTH_PTR-1:0] INDEX_PIXEL_LAST = COUNT_PIXELS - 1;

  logic [COUNT_PIXELS*8-1:0] pixels;

  genvar i;
  generate
    for (i = 0; i < COUNT_PIXELS; i = i + 1) begin : gen_pixels
      wire [ 7:0] r = s_axis_rx.tdata[i*32+0+:8];
      wire [ 7:0] g = s_axis_rx.tdata[i*32+8+:8];
      wire [ 7:0] b = s_axis_rx.tdata[i*32+16+:8];

      wire [15:0] grayscale = (r * 8'd77) + (g * 8'd150) + (b * 8'd29);
      assign pixels[i*8+:8] = grayscale[15:8];
    end
  endgenerate

  logic                 done;
  logic                 busy;
  logic [WIDTH_PTR-1:0] pixel_ptr;
  logic                 m_last_reg;

  typedef enum logic [1:0] {
    IDLE,
    ISSUE_CMD,
    WAIT_DATA,
    DONE_STATE
  } state_t;
  state_t state;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state                 <= IDLE;
      rd_desc_req.req_valid <= 1'b0;
      done                  <= 1'b0;
      busy                  <= 1'b0;
      m_valid               <= 1'b0;
      m_last                <= 1'b0;
    end else begin
      if (rd_desc_req.req_valid && rd_desc_req.req_ready) begin
        rd_desc_req.req_valid <= 1'b0;
      end

      case (state)
        IDLE: begin
          done <= 1'b0;
          if (run) begin
            rd_desc_req.req_valid <= 1'b1;
            state                 <= ISSUE_CMD;
          end
        end

        ISSUE_CMD: begin
          if (!rd_desc_req.req_valid) begin
            state <= WAIT_DATA;
          end
        end

        WAIT_DATA: begin
          if (s_axis_rx.tvalid && s_axis_rx.tready) begin
            busy       <= 1'b1;
            pixel_ptr  <= '0;
            m_valid    <= 1'b0;
            m_last     <= 1'b0;
            m_last_reg <= s_axis_rx.tlast;
          end else if (m_ready && busy) begin
            m_data    <= pixels[int'(pixel_ptr)*8+:8];
            m_valid   <= 1'b1;
            pixel_ptr <= pixel_ptr + 1;

            if (pixel_ptr == INDEX_PIXEL_LAST) begin
              busy <= 1'b0;

              if (m_last_reg) begin
                m_last <= 1'b1;
                done   <= 1'b1;
                state  <= DONE_STATE;
              end
            end
          end else begin
            m_valid <= 1'b0;
          end
        end

        DONE_STATE: begin
          m_valid <= 1'b0;
          if (!run) begin
            done  <= 1'b0;
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign s_axis_rx.tready = (state == WAIT_DATA) && !busy && (!m_valid || m_ready);

endmodule
