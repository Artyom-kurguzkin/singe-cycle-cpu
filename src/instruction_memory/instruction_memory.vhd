library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- InstructionMemory is the CPU's program ROM: a single-read-port, 1024 x
-- 32-bit memory (spec: "Instruction memory unit - A single read port memory
-- 1024 32-bit locations in size. All access will be on 32-bit boundaries
-- (ROM)"). This is one half of the Harvard-architecture split the spec asks
-- for (separate instruction memory and data memory, unlike ordinary MIPS,
-- which shares one memory for both) -- see data_mem.vhd (Step 5) for the
-- other half. The read is asynchronous/combinational: a real ROM has no
-- write port at all, so there is nothing to clock -- the output just always
-- reflects whatever Address currently points at.
entity InstructionMemory is
    Port (
        -- 10 bits wide because 2^10 = 1024, exactly the number of
        -- locations this ROM holds -- every possible Address value is a
        -- valid, in-range location, so there is no need for any bounds
        -- checking. This is also exactly the CPU's word-addressed PC width
        -- (see docs/cpu-implementation-plan.md section 2: "PC is
        -- word-addressed, not byte-addressed"), and matches the `jump`
        -- instruction's 10-bit absolute address field, which is presumably
        -- not a coincidence -- the spec sized the address space to exactly
        -- match what a `jump` can reach.
        Address        : in  STD_LOGIC_VECTOR (9 downto 0);

        -- The full 32-bit instruction word stored at Address.
        InstructionOut : out STD_LOGIC_VECTOR (31 downto 0)
    );
end InstructionMemory;

architecture Behavioral of InstructionMemory is

    -- Models the ROM contents as a plain array of 1024 32-bit words,
    -- indexed 0 to 1023 to match the 10-bit Address range exactly.
    type InstructionArrayType is array (0 to 1023) of STD_LOGIC_VECTOR (31 downto 0);

    -- nop's encoding (J-format, opcode 0x3f, address/unused fields
    -- irrelevant per the spec's instruction table): opcode occupies bits 31
    -- downto 26, so 0x3f ("111111") shifted into that position, with every
    -- other bit zero, is 0xFC000000. Used below to fill every placeholder
    -- address that isn't explicitly listed, so the placeholder program is
    -- at least a legally-encoded (if functionally meaningless) sequence of
    -- instructions rather than undefined memory contents.
    constant NopInstruction : STD_LOGIC_VECTOR (31 downto 0) := x"FC000000";

    -- Placeholder program contents, used only until Step 9 assembles the
    -- real Sieve of Eratosthenes program from Appendix 3 (see
    -- tools/assemble_sieve.py and docs/cpu-implementation-plan.md section
    -- 3/5). A handful of distinct, easy-to-recognise words at known
    -- addresses (including the very last one, to prove the full address
    -- range is wired up and not just the low end) let instr_mem_tb.vhd
    -- spot-check that reading a given address returns exactly the word
    -- that was stored there, independent of whatever the real program ends
    -- up containing.
    constant Instructions : InstructionArrayType := (
        0    => x"11111111",
        1    => x"22222222",
        2    => x"33333333",
        1023 => x"44444444",
        others => NopInstruction
    );

begin

    -- Asynchronous read: InstructionOut updates immediately whenever
    -- Address changes, with no clock involved at all -- matching a real
    -- ROM, which has no write port and therefore nothing to synchronise
    -- to. to_integer(unsigned(Address)) converts the 10-bit address vector
    -- into a plain integer 0-1023 to index into the Instructions array.
    InstructionOut <= Instructions(to_integer(unsigned(Address)));

end Behavioral;
