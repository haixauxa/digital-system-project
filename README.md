# RV32I FPGA Digital System

This project implements a complete digital system on a Tang Nano 9K. At its
centre is a five-stage RV32I processor written in Verilog. The processor boots
C firmware from an 8 KB instruction ROM, uses 4 KB of data RAM, reads date and
time from a DS3231 over I2C, and renders a clock interface on an ST7735
128x160 TFT over SPI. An external USB-UART provides the boot log and a command
for setting the RTC from a host computer.

## Objective

Design and implement a complete FPGA-based digital system around a five-stage
RV32I processor, using I2C to read time from a DS3231, SPI to display the clock
on an ST7735 TFT, and UART to communicate with a host computer.

## RV32I processor

RV32I is the 32-bit base integer instruction set of RISC-V. The processor
implements integer arithmetic and logic, shifts, signed and unsigned
comparisons, conditional branches, `JAL`, `JALR`, `LUI`, `AUIPC`, byte and
halfword loads and stores, word loads and stores, and `FENCE` as an ordering
no-op because the core is in-order and has no cache or write buffer. `ECALL`
and `EBREAK` are not implemented. Multiplication, division, floating point,
caches, virtual memory and an operating system are outside this design.

The CPU implements the RV32I integer datapath with IF, ID, EX, MEM and WB
stages. Forwarding, load-use interlocking and control-flow flushing are handled
in hardware. GPIO, UART, I2C and SPI are ordinary memory-mapped peripherals, so
firmware reaches them with normal loads and stores rather than custom CPU
instructions.

## Hardware and pinout

The target is a Tang Nano 9K carrying a Gowin GW1NR-LV9QN88PC6/I5 and using
the onboard 27 MHz oscillator. The external modules must share ground with the
FPGA. The ST7735 and DS3231 are powered from 3.3 V. SDA and SCL must never be
pulled up to 5 V, and the TFT backlight pin is tied directly to 3.3 V instead
of being driven by an FPGA I/O pin.

| Tang Nano 9K pin | RTL signal | Connection |
|---|---|---|
| 52 | `clk` | Onboard 27 MHz oscillator |
| 3 | `rst_n` | Onboard S2 reset button |
| 10 | `led_out` | Onboard active-low LED |
| 34 | `uart_tx_out` | RXD on the external USB-UART |
| 33 | `uart_rx_in` | TXD on the external USB-UART |
| 31 | `i2c_sda` | SDA on the DS3231 |
| 32 | `i2c_scl` | SCL on the DS3231 |
| 25 | `spi_sck_out` | SCK on the ST7735 |
| 26 | `spi_mosi_out` | SDA or MOSI on the ST7735 |
| 27 | `spi_cs_n_out` | CS on the ST7735 |
| 28 | `spi_dc_out` | AO or DC on the ST7735 |
| 29 | `spi_rst_n_out` | RESET on the ST7735 |
| 3V3 | — | VCC on the DS3231; VCC and LED on the ST7735 |
| GND | — | DS3231, ST7735 and USB-UART ground |

UART is crossed: FPGA TX connects to adapter RXD, and FPGA RX connects to
adapter TXD. Pins 25 through 29 are used for the external TFT rather than the
Tang Nano TF-card signals. The SPI link is write-only because the TFT breakout
does not expose MISO.

## System architecture

The instruction ROM occupies region `0x0` and also has a second port for
firmware constants and the load image of `.data`. Data RAM occupies region
`0x2`. The four peripherals use one region each:

| Base address | Device | Purpose |
|---|---|---|
| `0x00000000` | Instruction ROM | Instructions, `.rodata` and `.data` load image |
| `0x20000000` | Data RAM | Globals, `.bss` and stack |
| `0x40000000` | GPIO | Onboard LED |
| `0x50000000` | UART | 115200 8N1 transmit and 16-byte receive FIFO |
| `0x60000000` | I2C | Bidirectional DS3231 transactions at 50 kHz |
| `0x70000000` | SPI | Write-only ST7735 transfers at 6.75 MHz |

The I2C master supports repeated START, slave ACK and master ACK/NACK, allowing
firmware to set a register pointer and turn the bus around for a read. The SPI
master operates in mode 0 and shifts bytes most-significant bit first. The
firmware validates the DS3231 oscillator-stop flag, 24-hour mode, BCD fields,
field ranges and calendar date before presenting the value as a real clock.

## Toolchain

The command-line flow uses Icarus Verilog for RTL simulation, the bare-metal
RISC-V GCC toolchain for firmware, picocom for the serial console, and Gowin
EDA V1.9.12.03 for synthesis, place and route, bitstream generation and SRAM
programming. Install the Ubuntu packages with:

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  gcc-riscv64-unknown-elf \
  iverilog \
  gtkwave \
  picocom
```

The commands below use Gowin from this installation path:

```text
/home/haihbv/tools/Gowin_V1.9.12.03
```

Run every command from the project root:

```bash
cd /home/haihbv/Desktop/work/fpga
```

## Test, build and program

Run the complete verification suite first. It contains 33 RTL testbenches and
one host-side C test for DS3231 calendar validation:

```bash
make test
```

To inspect the UART MMIO waveform, compile the testbench together with the
optional VCD helper, run it, and open the generated trace in GTKWave:

```bash
mkdir -p build/sim
iverilog -g2012 \
  -s uart_mmio_tb -s dump_vcd \
  -o build/sim/uart.vvp \
  libs/uart/uart_tx.v \
  libs/uart/uart_rx.v \
  source/peripheral/uart_mmio.v \
  sim/peripheral/uart_mmio_tb.sv \
  sim/support/dump_vcd.sv
vvp build/sim/uart.vvp +vcd=build/sim/uart.vcd
gtkwave build/sim/uart.vcd
```

A successful run prints 34 `PASS` lines. Build the firmware next. This command
links the C and assembly sources and updates the ROM image committed at
`rom/firmware.hex`:

```bash
make firmware
```

Generate the FPGA bitstream with the Gowin headless flow:

```bash
make fpga
```

The resulting SRAM image is
`build/gowin/impl/pnr/fpga_project.fs`. Program it into the board with:

```bash
make program
```

The Makefile defaults `GOWIN_ROOT` to the installation path above. Override
it for another installation, for example `make fpga GOWIN_ROOT=/opt/Gowin`.

A successful programming operation reaches 100 percent and ends with
`Finished.`. The FPGA configuration is held in SRAM, so it must be programmed
again after removing board power.

## Console and RTC setup

Open the external USB-UART at 115200 baud, then press S2 to capture the boot
from its first line:

```bash
picocom -b 115200 --flow n /dev/ttyUSB0
```

A valid boot produces output similar to:

```text
BOOT 5A5A5A5A 00000000
TFT INIT
TFT BARS
RTC OSF CLEAR
RTC 2026-09-22 12:07:23
```

The two banner words check firmware startup: the first comes from `.data` and
the second from `.bss`. The TFT displays red, green and blue bars for one
second before switching to the clock interface. If the RTC oscillator-stop
flag is set or its registers do not contain a valid calendar value, the panel
shows `NOT SET` instead of displaying an untrusted reading.

To set the clock, exit picocom with `Ctrl-A`, then `Ctrl-X`. Configure the
serial device and send `WYYMMDDhhmmss`. This example sets
2026-09-22 12:30:00:

```bash
stty -F /dev/ttyUSB0 115200 raw -echo
printf 'W260922123000' > /dev/ttyUSB0
```

The firmware replies with `RTC SET OK`. An impossible date is rejected without
changing a clock that was already trusted:

```bash
printf 'W260231120000' > /dev/ttyUSB0
```

The response is `RTC SET RANGE`, and the existing time continues to run.

## Source tree

The tree is split by responsibility rather than by tool. `source/` contains
the SoC RTL, `libs/` contains reusable protocol engines and their unit tests,
and `sim/` contains integration and peripheral testbenches. Firmware is kept
under `sw/`; its generated boot image is committed under `rom/` because the
instruction ROM reads it during elaboration. Build, test and programming logic
is kept under `tools/`. `PROJECT_DECISIONS.txt` briefly records the reasons
behind the ROM size, the three external interfaces and the module boundaries.

```text
.
├── README.md                       # Project setup and operating guide
├── LICENSE                         # MIT License, copyright haibv10
├── PROJECT_DECISIONS.txt           # Short architecture decision notes
├── .gitignore                      # Local and generated file exclusions
├── fpga_project.gprj               # Gowin IDE project
│
├── constr/                         # Tang Nano 9K constraints
│   ├── fpga_project.cst            # Physical pin assignments
│   └── fpga_project.sdc            # 27 MHz timing constraint
│
├── source/                         # Synthesizable SoC RTL
│   ├── common/                     # Shared clock and reset blocks
│   │   ├── clock_enable.v
│   │   └── reset_sync.v
│   ├── cpu/                        # RV32I core, pipeline and memories
│   │   ├── cpu_top.v               # FPGA top module
│   │   ├── cpu_address_decoder.v   # ROM, RAM and MMIO region decoder
│   │   ├── core_*.v                # ALU, control, PC and register file
│   │   ├── pipe_*.v                # Pipeline registers and hazards
│   │   └── mem_*.v                 # Instruction ROM and data RAM
│   └── peripheral/                 # CPU-facing MMIO wrappers
│       ├── gpio_mmio.v
│       ├── uart_mmio.v
│       ├── i2c_mmio.v
│       └── spi_mmio.v
│
├── libs/                           # Reusable serial protocol engines
│   ├── uart/
│   │   ├── uart_tx.v
│   │   ├── uart_rx.v
│   │   └── *_tb.sv                 # UART unit tests
│   ├── i2c/
│   │   ├── i2c_master.v
│   │   ├── i2c_master_tb.sv
│   │   └── i2c_register_slave_model.sv  # Generic test slave
│   └── spi/
│       ├── spi_master.v
│       └── spi_master_tb.sv
│
├── sim/                            # Source-level integration tests
│   ├── common/                     # Common RTL tests
│   ├── cpu/                        # Core and full-SoC tests
│   ├── firmware/                   # Host-side firmware tests
│   ├── peripheral/                 # MMIO wrapper tests
│   └── support/
│       └── imem_test.hex           # Small ROM image used by ROM tests
│
├── sw/                             # Bare-metal firmware source
│   ├── main.c                      # Boot and main clock loop
│   ├── startup.s                   # .data/.bss setup and stack entry
│   ├── sys_delay.*                 # Calibrated busy-loop delay
│   ├── gpio_led.*                  # Onboard LED access
│   ├── uart_io.*                   # Console output and input
│   ├── i2c_bus.*                   # I2C MMIO frame access
│   ├── spi_bus.*                   # SPI MMIO byte access
│   ├── ds3231_rtc.*                # RTC read, validation and setup
│   ├── st7735_panel.*              # Panel init and drawing primitives
│   ├── font_8x8.*                  # Printable ASCII bitmap font
│   └── ui_clock.*                  # Clock screen layout
│
├── rom/
│   └── firmware.hex                # 8 KB instruction ROM image
│
└── tools/                          # Reproducible command-line flow
    ├── run_tests.sh                # Run all 34 tests
    ├── build_firmware.sh           # Compile firmware and update ROM image
    ├── linker_script.ld            # 8 KB ROM and 4 KB RAM layout
    ├── make_hex.py                 # Pad binary to the ROM depth
    ├── build_fpga.sh               # Start the headless Gowin build
    ├── build_gowin.tcl             # Gowin synthesis/P&R file list
    └── program_fpga.sh             # Program the SRAM bitstream
```

## Limitations

The ST7735 interface has no read path. The DS3231 is used in 24-hour mode and
the firmware represents years from 2000 through 2099. UART has no hardware
flow control, and its receive FIFO can overflow when software does not consume
bytes quickly enough.

## License

This project is released under the MIT License. Copyright (c) 2026 haibv10.
See `LICENSE` for the full terms.
