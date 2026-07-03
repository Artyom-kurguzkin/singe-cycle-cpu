STD     ?= 08
SRCDIR  := src
WAVEDIR := waves
WORKDIR := work

# ── FPGA settings ──────────────────────────────────────────────────────────────
BUILDDIR := build
PART     := xc7a100tcsg324-1
FAMILY   := artix7
BOARD    := nexys_a7_100
CHIPDB   ?= $(CHIPDB_DIR)/xc7a100t.bin

# ── Source files ───────────────────────────────────────────────────────────────
ALL_VHDL := $(shell find $(SRCDIR) -name '*.vhd')
SYN_VHDL := $(shell find $(SRCDIR) -name '*.vhd' \
              ! -name '*_tb.vhd' ! -name 'testbench*.vhd')

.PHONY: analyze sim synth pnr bitstream program fpga clean

# ── Simulation ─────────────────────────────────────────────────────────────────

analyze: $(ALL_VHDL)
	mkdir -p $(WORKDIR)
	ghdl -a --std=$(STD) -fsynopsys --workdir=$(WORKDIR) $(ALL_VHDL)

sim: analyze
ifndef TB
	$(error TB is not set. Usage: make sim TB=<testbench_entity_name>)
endif
	mkdir -p $(WAVEDIR)
	ghdl -e --std=$(STD) -fsynopsys --workdir=$(WORKDIR) $(TB)
	ghdl -r --std=$(STD) -fsynopsys --workdir=$(WORKDIR) $(TB) --vcd=$(WAVEDIR)/$(TB).vcd

# ── FPGA flow ──────────────────────────────────────────────────────────────────

synth:
ifndef TOP
	$(error TOP is not set. Usage: make synth TOP=<entity>)
endif
	mkdir -p $(BUILDDIR)
	yosys -m ghdl \
	  -p 'ghdl --std=$(STD) $(SYN_VHDL) -e $(TOP); \
	      synth_xilinx -flatten -abc9 -arch xc7 -top $(TOP); \
	      write_json $(BUILDDIR)/$(TOP).json'

pnr:
ifndef TOP
	$(error TOP is not set. Usage: make pnr TOP=<entity> XDC=<file.xdc>)
endif
ifndef XDC
	$(error XDC is not set. Usage: make pnr TOP=<entity> XDC=<file.xdc>)
endif
	nextpnr-xilinx \
	  --chipdb $(CHIPDB) \
	  --xdc $(XDC) \
	  --json $(BUILDDIR)/$(TOP).json \
	  --fasm $(BUILDDIR)/$(TOP).fasm

bitstream:
ifndef TOP
	$(error TOP is not set. Usage: make bitstream TOP=<entity>)
endif
	fasm2frames \
	  --part $(PART) \
	  --db-root $(PRJXRAY_DB_DIR)/$(FAMILY) \
	  $(BUILDDIR)/$(TOP).fasm > $(BUILDDIR)/$(TOP).frames
	xc7frames2bit \
	  --part_file $(PRJXRAY_DB_DIR)/$(FAMILY)/$(PART)/part.yaml \
	  --part_name $(PART) \
	  --frm_file $(BUILDDIR)/$(TOP).frames \
	  --output_file $(BUILDDIR)/$(TOP).bit

program:
ifndef TOP
	$(error TOP is not set. Usage: make program TOP=<entity>)
endif
	openFPGALoader --board $(BOARD) $(BUILDDIR)/$(TOP).bit

fpga:
ifndef TOP
	$(error TOP is not set. Usage: make fpga TOP=<entity> XDC=<file.xdc>)
endif
ifndef XDC
	$(error XDC is not set. Usage: make fpga TOP=<entity> XDC=<file.xdc>)
endif
	$(MAKE) synth     TOP=$(TOP)
	$(MAKE) pnr       TOP=$(TOP) XDC=$(XDC)
	$(MAKE) bitstream TOP=$(TOP)

clean:
	rm -rf $(WORKDIR) $(WAVEDIR) $(BUILDDIR)
