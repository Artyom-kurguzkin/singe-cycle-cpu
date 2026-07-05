library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- DataMemory is the other half of the Harvard-architecture split (see
-- instruction_memory.vhd for the program ROM half). Unlike a normal MIPS
-- design, load/store addresses here aren't just RAM -- the spec carves the
-- 256-value (8-bit) address space in half: "addresses 0 to 127 refer to
-- RAM, while 128 to 255 refer to the external IO." This entity is the
-- "write enable signal and a multiplexor" the spec asks for to make that
-- split happen. Per the spec, "the IO registers themselves do not need to
-- be implemented" here -- this module's job for the IO half of the address
-- space is only to *detect* an IO-range store and expose it on
-- IoAddress/IoData/IoEnable for something external (in this project, a
-- testbench) to observe; it must not also write that value into RAM.
entity DataMemory is
    Port (
        -- Drives the synchronous RAM write below. IO-range behaviour
        -- (IoAddress/IoData/IoEnable) is purely combinational and does not
        -- depend on Clock at all -- see the comment on IoEnable below for
        -- why.
        Clock             : in  STD_LOGIC;

        -- 8 bits wide to cover the full 0-255 address space described
        -- above. Bit 7 alone decides RAM vs IO: 0-127 has bit 7 = '0',
        -- 128-255 has bit 7 = '1'. The remaining 7 bits (6 downto 0) are
        -- exactly enough to index the 128-word RAM (2^7 = 128).
        Address           : in  STD_LOGIC_VECTOR (7 downto 0);

        -- The value to store this cycle -- typically rt's value for a
        -- `store` instruction (see docs/cpu-implementation-plan.md section
        -- 1's `store` semantics: `$rt -> mem($rs+immediate)`).
        WriteData         : in  STD_LOGIC_VECTOR (31 downto 0);

        -- Write enable for this whole module, driven by the control unit
        -- (asserted only for `store` instructions). Gates both the RAM
        -- write below and whether an IO-range access actually raises
        -- IoEnable.
        MemoryWriteEnable : in  STD_LOGIC;

        -- RAM's read data, valid for addresses 0-127. Per the spec, reads
        -- from the IO range (128-255) are "undefined/don't-care" -- this
        -- project's Sieve program never reads back from the IO range, so
        -- this output isn't given any special-cased behaviour for that
        -- case; it just reflects whatever RAM(Address(6 downto 0)) happens
        -- to hold either way (see the ReadData assignment at the bottom).
        ReadData          : out STD_LOGIC_VECTOR (31 downto 0);

        -- The three signals that expose an IO-range store to the outside
        -- world, wired straight through to the CPU's own
        -- ioaddress/iodata/ioenable ports per the spec ("Your CPU component
        -- should include ports connecting these signals to a toplevel
        -- component").
        IoAddress         : out STD_LOGIC_VECTOR (7 downto 0);
        IoData            : out STD_LOGIC_VECTOR (31 downto 0);
        IoEnable          : out STD_LOGIC
    );
end DataMemory;

architecture Behavioral of DataMemory is

    -- Models the 128-word RAM half of the address space. Indexed 0 to 127,
    -- matching Address(6 downto 0) exactly regardless of whether Address
    -- as a whole falls in the RAM or IO half.
    type RamArrayType is array (0 to 127) of STD_LOGIC_VECTOR (31 downto 0);
    signal Ram : RamArrayType := (others => (others => '0'));

    -- '1' when Address falls in the memory-mapped-IO half (128-255), '0'
    -- when it falls in the RAM half (0-127). This is just bit 7 of Address
    -- on its own, named so the rest of the architecture reads clearly
    -- instead of repeating "Address(7)" everywhere.
    signal IsIoAddress : STD_LOGIC;

begin

    IsIoAddress <= Address(7);

    -- The RAM's single write port: synchronous, and only when both
    -- MemoryWriteEnable is asserted (this is a `store` instruction) *and*
    -- the address actually falls in the RAM half. The second condition is
    -- what stops an IO-range store from also corrupting RAM at the aliased
    -- index Address(6 downto 0) -- without it, storing to e.g. address 128
    -- (IO) would silently also write RAM(0), which is exactly the bug the
    -- spec's write-enable-plus-multiplexor requirement exists to prevent.
    RamWritePort: process (Clock)
    begin
        if rising_edge(Clock) then
            if MemoryWriteEnable = '1' and IsIoAddress = '0' then
                Ram(to_integer(unsigned(Address(6 downto 0)))) <= WriteData;
            end if;
        end if;
    end process;

    -- Asynchronous RAM read, mirroring instruction_memory.vhd's read style
    -- -- the value at Address(6 downto 0) is always available combinationally,
    -- with no clock involved. Meaningless (but harmless) when Address falls
    -- in the IO half, per the spec's "reads from IO are don't-care."
    ReadData <= Ram(to_integer(unsigned(Address(6 downto 0))));

    -- IoAddress/IoData are driven straight through combinationally rather
    -- than latched -- the spec doesn't ask for the IO registers themselves
    -- to be implemented, only for this module to expose what a store
    -- targeting the IO range would have sent. Whatever's observing these
    -- (in this project, a testbench) is expected to sample them while
    -- IoEnable = '1', which -- since this is a single-cycle CPU where
    -- MemoryWriteEnable/Address stay stable for an entire clock period --
    -- means they're valid for the whole cycle a `store`-to-IO instruction
    -- executes, not just a single simulation delta-cycle.
    IoAddress <= Address;
    IoData    <= WriteData;

    -- IoEnable pulses '1' for exactly the cycle a store instruction targets
    -- the IO half of the address space -- i.e. exactly the case the RAM
    -- write above deliberately excludes. Purely combinational (not
    -- registered) for the same reason IoAddress/IoData are: nothing else
    -- in this design needs it clocked, and keeping it combinational avoids
    -- a one-cycle lag between "the store instruction executes" and
    -- "IoEnable reflects it."
    IoEnable <= '1' when (MemoryWriteEnable = '1' and IsIoAddress = '1') else '0';

end Behavioral;
