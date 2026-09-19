# PCIe SGDMA + DDR3 + Convolution for Sipeed Tang Mega 138K Pro

FPGA-based 2D image convolution over PCIe and DDR3 on the [Sipeed Tang Mega 138K Pro Dock](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k-pro.html): the host streams an image to the board, the FPGA convolves it in DDR3, and streams the result back.

This continues [pci-ddr-gowin-tangmega138kpro](https://github.com/Lamagraph/pci-ddr-gowin-tangmega138kpro) — a demo of the PCIe Controller, PCIe SGDMA, and DDR3 Memory Interface. Built for the [intro-to-fpga-with-clash](https://github.com/Lamagraph/intro-to-fpga-with-clash) course.

## Key Features

- **PCIe Controller**: SerDes-based Gowin IP core that provides the link between the PCIe host and the FPGA. Paired with the PCIe SGDMA IP, which provides Scatter-Gather DMA communication over two channels (H2C/C2H). No manual TLP parsing in this project.
- **DDR3 Memory Controller**: Gowin IP core that provides the interface to the DDR3 chip — the memory itself holds the incoming image and the convolution result before it is sent back to the host.
- **AXI4 Interface**: open-source AXI4 components connect PCIe SGDMA and the convolution core to DDR3. Two AXI4 DMA engines convert the SGDMA and convolution AXI4-streams to AXI4. An AXI interconnect connects them to the DDR3 controller. Two async FIFOs cross the H2C/C2H streams between clock domains.
- **Convolution**: reads image data from DDR3 and writes the filtered result back over AXI4-Stream. Convolution architecture is in [convolution-pipeline.svg](convolution-pipeline.svg).
- **PCIe driver**: Linux kernel module that links the board to the host — enables the device, maps the BAR windows, and allocates/exposes DMA buffers to the host application.
- **Host application**: drives the full transfer pipeline — builds DMA descriptors, starts the SGDMA controller, polls for completion, and validates the data returned from the board.

> See full architecture in [architecture.pdf](architecture.pdf).

## Project Structure

```text
| -- fpga/                --> FPGA-side sources and build artifacts
|    |-- project.fs.7z    --> Prebuilt archived bitstream
|    |-- project.gar      --> Gowin IDE project archive
|    |-- project.tcl      --> Gowin IDE project generation script
|    `-- project/         --> Gowin IDE project sources
|
| -- host/                --> Host-side software
|    |-- driver/          --> Linux PCIe kernel driver
|    |-- app/             --> Host application
|    |-- bin/             --> Compiled binary and run script
|    |-- include/         --> Shared headers (driver interface, BAR layout, descriptor format)
|    `-- Makefile         --> Build entry point for the driver and application
```

## How to Use

### Preparation

- **Gowin IDE**: version >= 1.9.12.02 recommended. SerDes IP generation specifically requires V1.9.12.02.
- **Linux Environment**: Ubuntu 22.04/24.04 recommended.
- **Boot Configuration**:
  - `pci=realloc=on` (only on kernel version >= 6.17), `iommu=pt`.
  - **Secure Boot**: must be **disabled**. Unsigned kernel modules will be blocked by UEFI Secure Boot unless you manually sign them and enroll the key in MOK.

> Working scenario: laptop with Gowin IDE V1.9.12.02 for programming & PC with Ubuntu 22.04 (6.8) as host (also Ubuntu 22.04 (5.15) and Ubuntu 24.04 (6.17) with `pci=realloc=on`).

### Build & Load FPGA

The IP cores used in this project (SerDes/PCIe Controller, PCIe SGDMA, DDR3 Memory Interface, PLL) are Gowin-generated. Their encrypted output files are not committed to this repository — only the configuration (`.ipc`) files and usage examples produced alongside them are included. To reproduce the project you need to regenerate the IP cores in Gowin IDE, or restore them from the archives included in this repository.

**Option A — from the `.tcl` script:**

1. Create the Gowin IDE project with the script: `gw_sh project.tcl`.
2. Generate the IP cores listed below inside the project via `IP Core Generator`, using the parameters given for each.
3. Synthesize and generate the bitstream (`.fs`).
4. Load to the board via **Gowin Programmer** or **openFPGAloader**.
   > _Note: after programming, reboot the host PC._

| Core                     | Generator path                                                                                                       | Key settings                                                                                                                                                                                        |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SerDes / PCIe Controller | `IP Core Generator` → `Soft IP Core` → `SerDes` → `SerDes`, Protocol: `PCI Express Controller`                       | `Vendor/Device ID` is `22c2`/`1100`; `Lane Width`, `Max Link Speed`, `Max Payload Size` at maximum; `TLP Clock Frequency` is 100 MHz; `BAR0` — SGDMA control, `BAR2` — user registers (both 64-bit) |
| PCIe SGDMA               | `IP Core Generator` → `Soft IP Core` → `Interface and Interconnect` → `PCIe SGDMA`                                   | -                                                                                                                                                                                                   |
| DDR3 Memory Interface    | `IP Core Generator` → `Soft IP Core` → `Memory Controller` → `DDRx SDRAM Memory Interface` → `DDR3 Memory Interface` | Enable `AXI4 Interface` with `Mode4`; `Dq Width` is 32, `Dram Width` is 16; `Row` is 15, `Column` is 10 (for 1 GB)                                                                                  |
| PLL                      | `IP Core Generator` → `Hard Module` → `CLOCK` → `PLL_ADV`                                                            | `CLKIN` is 100 MHz, `CLKOUT0` is 400 MHz; enable `PLL Reset`, `Enable Lock`, and `Clock Enable Ports` on the `Common` tab                                                                           |

> Additional generation options are stored in the corresponding `.ipc` files.

**Option B — from the prebuilt bitstream:**

Unzip `fpga/project/project.fs.7z` and go straight to step 4 above.

**Option C — from the archived project:**

Restore `fpga/project/project.gar` via `Project` → `Restore Archived Project`. The IP cores inside the archive keep the file paths of the machine they were generated on, so restoring `project.gar` elsewhere is not guaranteed to reproduce the same build — if it fails, fall back to `Option A` and regenerate the IP cores from scratch.

> We did successfully unpack and build the [demo project archive](<https://github.com/sipeed/TangMega-138KPro-example/tree/main/pcie_dma_demo/pcie_gen3(8G)>) this way.

### Build & Run Host

0. Check if the device is recognized: `sudo lspci -vvd 22c2:1100`.
1. Navigate to the `host/` directory: `cd host`.
2. Build the driver and applications: `sudo make`.
3. Run the tests: `./bin/run_app`. Choose options for the transfer:
   - data size: the size of the data stored in host RAM and transferred to the board;
   - block size: the size of the data described by a single descriptor (for testing);
   - dump option: the ability to dump data before and after transmission.

## LEDs

Status indication on the Dock (LED0 is on the far right):

| LEDs | Description                  | Expected State         |
| ---- | ---------------------------- | ---------------------- |
| LED0 | RUNNING INDICATOR            | BLINKING               |
| LED1 | PCIe RESET (L23)             | OFF (see note)         |
| LED2 | PCIe LOGIC START             | ON                     |
| LED3 | PCIe LINK UP                 | ON                     |
| LED4 | DDR3 Initialization Complete | ON                     |
| LED5 | PCIe H2C RUNNING             | OFF (ON while running) |

> _NOTE: LED1 (PCIe RESET) may flash briefly during boot. But this LED should not be always ON, otherwise please check whether the relevant **PIN(L23)** in the project is constrained to **PULL_UP** mode._

## Implementation Details

- **Clocks**:
  - `sys_clk` (200 MHz) and `memory_clk` (400 MHz) come from the on-board PLL.
  - `tlp_clk` (100 MHz, ÷2 from `sys_clk`) clocks the PCIe Controller and SGDMA logic.
  - The DDR3 controller runs its own output clock, `ui_clk` (100 MHz, ÷4 from `memory_clk`), which clocks the AXI interconnect, both AXI DMA engines, and the convolution core.
- **Reset**:
  - The design comes out of reset once the PCIe startup delay elapses and the DDR3 controller finishes calibration (`init_calib_complete`).
  - Button **S0 (K16)** resets the transmission.
- **Interfaces**: `BAR0` is used for SGDMA control, `BAR2` is user-accessible for custom registers/convolution control.

## Links

- [Tang MEGA 138K Pro Wiki](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k-pro.html)
- [Gowin SerDes / PCIe Controller IP User Guide](https://cdn.gowinsemi.com.cn/IPUG1020E.pdf) & [PCIe DMA demo](https://github.com/sipeed/TangMega-138KPro-example/tree/main/pcie_dma_demo)
- [Gowin PCIe SGDMA IP User Guide](https://cdn.gowinsemi.com.cn/IPUG1527E.pdf)
- [Gowin DDR3 Memory Interface IP User Guide](https://cdn.gowinsemi.com.cn/IPUG281E.pdf) & [DDR test](https://github.com/sipeed/TangMega-138KPro-example/tree/main/ddr_test)
- [Taxi (FPGA Ninja / Alex Forencich)](https://github.com/fpganinja/taxi)
