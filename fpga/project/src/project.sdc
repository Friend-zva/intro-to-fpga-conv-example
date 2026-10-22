create_clock -name sys_clk_p  // 50 MHz
  -period 20 -waveform {0 10}
  [get_ports {sys_clk_p}]

create_generated_clock -name tlp_clk  // 100 MHz
  -source [get_ports {sys_clk_p}]
  -master_clock sys_clk_p
  -multiply_by 2 [get_pins {u_pll/u_pll_0/PLL_inst/CLKOUT1}]

create_generated_clock -name memory_clk  // 400 MHz
  -source [get_ports {sys_clk_p}]
  -master_clock sys_clk_p
  -multiply_by 8 [get_pins {u_pll/u_pll_0/PLL_inst/CLKOUT3}]

create_generated_clock -name ddr_out_clk  // 100 MHz
  -source [get_pins {u_pll/u_pll_0/PLL_inst/CLKOUT3}]
  -master_clock memory_clk
  -divide_by 4 [get_pins {u_ddr3/gw3_top/u_GW_DDR3_PHY_MC/u_ddr_phy_top/fclkdiv/CLKOUT}]

set_clock_groups -asynchronous
  -group [get_clocks {sys_clk_p}]
  -group [get_clocks {tlp_clk}]
  -group [get_clocks {memory_clk}]
  -group [get_clocks {ddr_out_clk}]
