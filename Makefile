STD     ?= 08
SRCDIR  := src
WAVEDIR := waves
WORKDIR := work

VHDL_FILES := $(shell find $(SRCDIR) -name '*.vhd')

.PHONY: analyze sim clean

analyze: $(VHDL_FILES)
	mkdir -p $(WORKDIR)
	ghdl -a --std=$(STD) -fsynopsys --workdir=$(WORKDIR) $(VHDL_FILES)

sim: analyze
ifndef TB
	$(error TB is not set. Usage: make sim TB=<testbench_entity_name>)
endif
	mkdir -p $(WAVEDIR)
	ghdl -e --std=$(STD) -fsynopsys --workdir=$(WORKDIR) $(TB)
	ghdl -r --std=$(STD) -fsynopsys --workdir=$(WORKDIR) $(TB) --vcd=$(WAVEDIR)/$(TB).vcd

clean:
	rm -rf $(WORKDIR) $(WAVEDIR)
