SIM := iverilog
VVP := vvp

FLAGS := -g2012
PROJECT := project
SIM_DIR := $(PROJECT)/sim
BUILD ?= $(SIM_DIR)/build

APP_SOURCES := $(shell find $(PROJECT)/src/convolution -type f -name '*.sv') $(PROJECT)/src/logic_conv.sv $(PROJECT)/src/top.sv $(PROJECT)/src/manager_logic.sv
TBS_SOURCES := $(sort $(shell find $(SIM_DIR)/tb -type f -name '*.sv'))

TB ?=
NAME = $(basename $(notdir $(TB)))
DEPS ?= $(DEPS_$(NAME))
OUT = $(BUILD)/$(NAME).vvp

INTERFACES = $(PROJECT)/src/taxi/taxi_dma_desc_if.sv $(PROJECT)/src/taxi/taxi_axis_if.sv
CONV2D = $(PROJECT)/src/convolution
CONV1D = $(CONV2D)/middle/conv1d.sv $(CONV2D)/middle/window.sv $(CONV2D)/middle/scalar_product.sv $(CONV2D)/middle/float_mult_byte.sv
FRONT = $(CONV2D)/front/demux.sv $(CONV2D)/front/line_buffer.sv $(CONV2D)/front/mux.sv $(SIM_DIR)/gowin_sp_sim.sv

DEPS_demux_tb 									= $(CONV2D)/front/demux.sv
DEPS_mux_tb 										= $(CONV2D)/front/mux.sv
DEPS_line_buffer_tb 						= $(CONV2D)/front/line_buffer.sv $(SIM_DIR)/gowin_sp_sim.sv
DEPS_rgb_to_grayscale_stream_tb = $(INTERFACES) $(CONV2D)/front/rgb_to_grayscale_stream.sv

DEPS_kernel_loader_tb 	= $(CONV2D)/middle/kernel_loader.sv $(SIM_DIR)/gowin_rom_sim.sv
DEPS_float_mult_byte_tb = $(CONV2D)/middle/float_mult_byte.sv
DEPS_window_tb 					= $(CONV2D)/middle/window.sv
DEPS_conv1d_tb 					= $(CONV1D)

DEPS_grayscale_stream_tb = $(INTERFACES) $(CONV2D)/back/grayscale_stream.sv
DEPS_ping_pong_buffer_tb = $(CONV2D)/back/ping_pong_buffer.sv $(SIM_DIR)/gowin_sp_sim.sv

DEPS_demux_mux_tb = $(FRONT)
DEPS_demux_ppb_tb = $(FRONT) $(CONV1D) $(CONV2D)/middle/adder.sv $(CONV2D)/back/ping_pong_buffer.sv

.DEFAULT_GOAL := $(if $(TB),test,all)
.PHONY: all test list format $(APP_SOURCES) lint clean

all:
	@for tb in $(TBS_SOURCES); do \
		$(MAKE) --no-print-directory test TB="$$tb" || exit 1; \
	done

test:
	@test -n "$(TB)" && test -f "$(TB)" || \
	  (echo "Invalid TB [$(TB)]: specify an existing testbench"; exit 2)
	@test -n "$(DEPS)" || \
	  (echo "Invalid DEPS [$(TB)]: specify DUT sources and dependencies"; exit 2)
	@test -n "$(NAME)" || \
	  (echo "Invalid NAME [$(TB)]: specify the testbench module"; exit 2)
	@mkdir -p "$(BUILD)"
	$(SIM) $(FLAGS) -s $(NAME) -o "$(OUT)" $(DEPS) $(TB)
	$(VVP) "$(OUT)"

list:
	@printf '%s\n' $(TBS_SOURCES)

format: $(APP_SOURCES)

$(APP_SOURCES):
	verible-verilog-format --flagfile=.verilog_format --verify $@

lint:
	verible-verilog-lint --rules_config=.rules.verible_lint $(APP_SOURCES)

clean:
	rm -rf "$(BUILD)"
