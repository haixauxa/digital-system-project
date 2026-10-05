GOWIN_ROOT ?= /home/haihbv/tools/Gowin_V1.9.12.03
FLASH_FREQ ?= 1000000

.PHONY: help test firmware fpga program flash

help:
	@printf '%s\n' \
	  'make test      Run all RTL and firmware tests.' \
	  'make firmware  Build the RISC-V firmware ROM image.' \
	  'make fpga      Build firmware and generate the FPGA bitstream.' \
	  'make program   Build the bitstream and program FPGA SRAM.' \
	  'make flash     Build the bitstream and program persistent Flash.' \
	  'Set GOWIN_ROOT=/path/to/Gowin to override the default installation.'

test:
	bash tools/run_tests.sh

firmware:
	bash tools/build_firmware.sh

fpga: firmware
	GOWIN_ROOT="$(GOWIN_ROOT)" bash tools/build_fpga.sh

program: fpga
	sudo env GOWIN_ROOT="$(GOWIN_ROOT)" bash tools/program_fpga.sh

flash: fpga
	sudo env OPENFPGALOADER_FREQ="$(FLASH_FREQ)" bash tools/program_flash.sh
