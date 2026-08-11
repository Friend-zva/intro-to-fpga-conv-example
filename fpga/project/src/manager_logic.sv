module manager_logic #(
    parameter integer AXI_ADDR_WIDTH = 29,
    parameter integer AXI_LEN_WIDTH  = 20
) (
    input clk,
    input rst_n,

    // BAR2 PCIe Sgdma
    input             user_cs,
    input      [63:0] user_address,
    input             user_rw,
    input      [31:0] user_wr_data,
    output reg        user_rd_valid,
    output reg [31:0] user_rd_data,
    input      [63:0] h2c_overhead_reg,

    // AXI DMA Descriptors
    taxi_dma_desc_if.req_src desc_h2c,
    taxi_dma_desc_if.req_src desc_c2h,

    // Logic Core Config
    output reg [AXI_ADDR_WIDTH-1:0] lcore_read_addr,
    output reg [AXI_ADDR_WIDTH-1:0] lcore_write_addr,
    output reg [ AXI_LEN_WIDTH-1:0] lcore_len,
    output reg                      lcore_run,
    input                           lcore_done
);
  //* All lengths in bytes.

  assign desc_h2c.req_tag = '0;
  assign desc_c2h.req_tag = '0;

  localparam integer USR_ADDR_WIDTH = 8;

  localparam [USR_ADDR_WIDTH-1:0] RegCtrl = 8'h00;
  localparam [USR_ADDR_WIDTH-1:0] RegStatus = 8'h04;
  localparam [USR_ADDR_WIDTH-1:0] RegAddrDDRh2c = 8'h10;
  localparam [USR_ADDR_WIDTH-1:0] RegLengDDRh2c = 8'h14;
  localparam [USR_ADDR_WIDTH-1:0] RegOverheadh2cLo = 8'h18;
  localparam [USR_ADDR_WIDTH-1:0] RegOverheadh2cHi = 8'h1C;
  localparam [USR_ADDR_WIDTH-1:0] RegAddrDDRc2h = 8'h20;
  localparam [USR_ADDR_WIDTH-1:0] RegLengDDRc2h = 8'h24;
  localparam [USR_ADDR_WIDTH-1:0] RegAddrLcoreRd = 8'h30;
  localparam [USR_ADDR_WIDTH-1:0] RegAddrLcoreWr = 8'h34;
  localparam [USR_ADDR_WIDTH-1:0] RegLengLcore = 8'h38;

  wire wr_en = user_cs && user_rw;
  wire rd_en = user_cs && !user_rw;
  wire [USR_ADDR_WIDTH-1:0] addr_reg = user_address[USR_ADDR_WIDTH-1:0];

  reg lcore_done_latched;
  reg lcore_start_pulse;
  reg lcore_stop_pulse;

  // lcore
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lcore_run <= 1'b0;
      lcore_done_latched <= 1'b0;
    end else begin
      if (lcore_done) begin
        lcore_run <= 1'b0;
        lcore_done_latched <= 1'b1;
      end

      if (lcore_start_pulse) begin
        lcore_run <= 1'b1;
        lcore_done_latched <= 1'b0;
      end

      if (lcore_stop_pulse) begin
        lcore_run <= 1'b0;
      end
    end
  end

  // BAR2 host write
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      desc_h2c.req_dst_addr <= {AXI_ADDR_WIDTH{1'b0}};
      desc_h2c.req_len <= {AXI_LEN_WIDTH{1'b0}};
      desc_h2c.req_valid <= 1'b0;

      desc_c2h.req_src_addr <= {AXI_ADDR_WIDTH{1'b0}};
      desc_c2h.req_len <= {AXI_LEN_WIDTH{1'b0}};
      desc_c2h.req_valid <= 1'b0;

      lcore_read_addr <= {AXI_ADDR_WIDTH{1'b0}};
      lcore_write_addr <= {AXI_ADDR_WIDTH{1'b0}};
      lcore_len <= {AXI_LEN_WIDTH{1'b0}};

      lcore_start_pulse <= 1'b0;
      lcore_stop_pulse <= 1'b0;
    end else begin
      lcore_start_pulse <= 1'b0;
      lcore_stop_pulse  <= 1'b0;

      if (desc_h2c.req_valid && desc_h2c.req_ready) begin
        desc_h2c.req_valid <= 1'b0;
      end
      if (desc_c2h.req_valid && desc_c2h.req_ready) begin
        desc_c2h.req_valid <= 1'b0;
      end

      if (wr_en) begin
        case (addr_reg)
          RegCtrl: begin
            // bit0: start pcie write descriptor
            // bit1: stop  pcie write descriptor
            // bit2: start pcie read  descriptor
            // bit3: stop  pcie read  descriptor
            // bit4: start logic core
            // bit5: stop  logic core
            if (user_wr_data[0]) begin
              desc_h2c.req_valid <= 1'b1;
            end
            if (user_wr_data[1]) begin
              desc_h2c.req_valid <= 1'b0;
            end
            if (user_wr_data[2]) begin
              desc_c2h.req_valid <= 1'b1;
            end
            if (user_wr_data[3]) begin
              desc_c2h.req_valid <= 1'b0;
            end
            if (user_wr_data[4]) begin
              lcore_start_pulse <= 1'b1;
            end
            if (user_wr_data[5]) begin
              lcore_stop_pulse <= 1'b1;
            end
          end

          RegAddrDDRh2c: begin
            desc_h2c.req_dst_addr <= user_wr_data[AXI_ADDR_WIDTH-1:0];
          end
          RegLengDDRh2c: begin
            desc_h2c.req_len <= user_wr_data[AXI_LEN_WIDTH-1:0];
          end

          RegAddrDDRc2h: begin
            desc_c2h.req_src_addr <= user_wr_data[AXI_ADDR_WIDTH-1:0];
          end
          RegLengDDRc2h: begin
            desc_c2h.req_len <= user_wr_data[AXI_LEN_WIDTH-1:0];
          end

          RegAddrLcoreRd: begin
            lcore_read_addr <= user_wr_data[AXI_ADDR_WIDTH-1:0];
          end
          RegAddrLcoreWr: begin
            lcore_write_addr <= user_wr_data[AXI_ADDR_WIDTH-1:0];
          end
          RegLengLcore: begin
            lcore_len <= user_wr_data[AXI_LEN_WIDTH-1:0];
          end

          default: begin
          end
        endcase
      end
    end
  end

  // BAR2 host read
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      user_rd_valid <= 1'b0;
      user_rd_data  <= 32'd0;
    end else begin
      user_rd_valid <= 1'b0;

      if (rd_en) begin
        user_rd_valid <= 1'b1;
        case (addr_reg)
          RegCtrl: user_rd_data <= 32'd0;
          RegStatus: begin
            user_rd_data[0] <= desc_c2h.req_valid;
            user_rd_data[1] <= desc_h2c.req_valid;
            user_rd_data[2] <= desc_c2h.req_ready;
            user_rd_data[3] <= desc_h2c.req_ready;
            user_rd_data[4] <= lcore_run;
            user_rd_data[5] <= lcore_done_latched;
            user_rd_data[31:6] <= 26'd0;
          end

          RegAddrDDRh2c: begin
            user_rd_data <= {{(32 - AXI_ADDR_WIDTH) {1'b0}}, desc_h2c.req_dst_addr};
          end
          RegLengDDRh2c: begin
            user_rd_data <= {{(32 - AXI_LEN_WIDTH) {1'b0}}, desc_h2c.req_len};
          end

          RegOverheadh2cLo: begin
            user_rd_data <= h2c_overhead_reg[31:0];
          end
          RegOverheadh2cHi: begin
            user_rd_data <= h2c_overhead_reg[63:32];
          end

          RegAddrDDRc2h: begin
            user_rd_data <= {{(32 - AXI_ADDR_WIDTH) {1'b0}}, desc_c2h.req_src_addr};
          end
          RegLengDDRc2h: begin
            user_rd_data <= {{(32 - AXI_LEN_WIDTH) {1'b0}}, desc_c2h.req_len};
          end

          RegAddrLcoreRd: begin
            user_rd_data <= {{(32 - AXI_ADDR_WIDTH) {1'b0}}, lcore_read_addr};
          end
          RegAddrLcoreWr: begin
            user_rd_data <= {{(32 - AXI_ADDR_WIDTH) {1'b0}}, lcore_write_addr};
          end
          RegLengLcore: begin
            user_rd_data <= {{(32 - AXI_LEN_WIDTH) {1'b0}}, lcore_len};
          end

          default: begin
            user_rd_data <= 32'd0;
          end
        endcase
      end
    end
  end

endmodule
