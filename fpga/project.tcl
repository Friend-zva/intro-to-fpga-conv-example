create_project -name project -pn GW5AST-LV138FPG676AC1/I0 -device_version B -force
set_option -output_base_name project

add_file -type cst "./src/project.cst"
add_file -type sdc "./src/project.sdc"

set_option -enable_dsrm 0
set_option -synthesis_tool gowinsynthesis
set_option -top_module top
set_option -verilog_std sysv2017
set_option -rw_check_on_ram 1
set_option -place_option 1
set_option -route_option 1
set_option -clock_route_order 1
set_option -use_sspi_as_gpio 1
set_option -use_cpu_as_gpio 1
set_option -bit_compress 1
set_option -loading_rate 210/2
set_option -serdesRetiming 1

source "./structure.tcl"
