module rgb_to_grayscale_stream #(
  parameter int AXI_DATA_WIDTH = 256,
  parameter int AXI_ADDR_WIDTH = 29,
  parameter int AXI_LEN_WIDTH  = 20
) (
  input logic clk,
  input logic rst_n,

  input logic [AXI_ADDR_WIDTH-1:0] cfg_read_addr,
  input logic [ AXI_LEN_WIDTH-1:0] cfg_len,

  taxi_dma_desc_if.req_src rd_desc_req,
  taxi_axis_if.snk         s_axis_rx,

  input  logic       m_ready,
  output logic       m_valid,
  output logic       m_last,
  output logic [7:0] m_data,

  input logic run
);
  localparam int COUNT_PIXELS = AXI_DATA_WIDTH / 32;
  localparam int WIDTH_PTR = (COUNT_PIXELS > 1) ? $clog2(COUNT_PIXELS) : 1;
  localparam logic [WIDTH_PTR-1:0] INDEX_PIXEL_LAST = COUNT_PIXELS - 1;

  logic [COUNT_PIXELS*8-1:0] pixels;

  for (genvar i = 0; i < COUNT_PIXELS; i = i + 1) begin : gen_pixels
    logic [7:0] r, g, b;
    logic [15:0] grayscale;
    assign r              = s_axis_rx.tdata[i*32+0+:8];
    assign g              = s_axis_rx.tdata[i*32+8+:8];
    assign b              = s_axis_rx.tdata[i*32+16+:8];
    assign grayscale      = (r * 8'd77) + (g * 8'd150) + (b * 8'd29);
    assign pixels[i*8+:8] = grayscale[15:8];
  end

  logic busy;
  logic m_last_reg;

  logic [COUNT_PIXELS*8-1:0] pixels_reg;
  logic [     WIDTH_PTR-1:0] pixel_ptr;

  typedef enum logic [1:0] {
    IDLE,
    ISSUE_CMD,
    WAIT_DATA,
    DONE_STATE
  } state_t;
  state_t state;

  assign s_axis_rx.tready = (state == WAIT_DATA) && !busy;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_desc_req.req_src_addr <= '0;
      rd_desc_req.req_len      <= '0;
    end else if (state == IDLE && run) begin
      rd_desc_req.req_src_addr <= cfg_read_addr;
      rd_desc_req.req_len      <= cfg_len;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state                 <= IDLE;
      rd_desc_req.req_valid <= 1'b0;
      busy                  <= 1'b0;
      pixel_ptr             <= '0;
      pixels_reg            <= '0;
      m_last_reg            <= 1'b0;
    end else begin
      if (rd_desc_req.req_valid && rd_desc_req.req_ready) begin
        rd_desc_req.req_valid <= 1'b0;
      end

      case (state)
        IDLE: begin
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
            pixels_reg <= pixels;
            m_last_reg <= s_axis_rx.tlast;
          end else if (m_ready && busy) begin
            pixel_ptr <= pixel_ptr + 1'b1;

            if (pixel_ptr == INDEX_PIXEL_LAST) begin
              busy <= 1'b0;

              if (m_last_reg) begin
                state <= DONE_STATE;
              end
            end
          end
        end

        DONE_STATE: begin
          if (!run) begin
            state <= IDLE;
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

  assign m_valid = busy;
  assign m_last  = m_last_reg && pixel_ptr == INDEX_PIXEL_LAST;
  assign m_data  = pixels_reg[int'(pixel_ptr)*8+:8];

endmodule
