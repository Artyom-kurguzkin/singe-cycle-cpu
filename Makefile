STD     ?= 08
SRCDIR  := src
WAVEDIR := waves
WORKDIR := work

# program_loader_pkg.vhd must be analyzed before anything that `use`s it
# (VHDL package analysis is order-dependent, unlike component-instantiated
# entities, which only bind at elaboration) -- listed explicitly first
# rather than relying on find's alphabetical default, which would put
# several consuming testbenches ahead of it.
PKG_FILES := src/instruction_memory/program_loader_pkg.vhd

OTHER_VHDL_FILES := $(filter-out $(PKG_FILES), $(shell find $(SRCDIR) -name '*.vhd' -not -path '$(SRCDIR)/example/*'))

VHDL_FILES := $(PKG_FILES) $(OTHER_VHDL_FILES)

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
