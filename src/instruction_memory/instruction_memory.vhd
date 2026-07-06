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
--
-- ProgramData is a generic, not a port: a real ROM's contents are fixed at
-- fabrication, which a generic (resolved once at elaboration) models far
-- more honestly than a port (which implies a value that could change
-- during simulation, which this never does after elaboration). This entity
-- has no idea how that value gets produced -- it just receives it, already
-- fully formed. Whatever actually reads a program file
-- (ProgramLoaderPkg.LoadProgramFromFile, see program_loader_pkg.vhd) is a
-- plain function called only by testbenches -- reading a file is
-- inherently non-synthesizable, so it has no business anywhere inside this
-- entity, or inside cpu.vhd's structural hardware description either. This
-- mirrors a real system: a ROM chip has no idea what firmware decided to
-- burn into it.
entity InstructionMemory is
    Generic (
        -- No default -- whatever instantiates this entity must say
        -- explicitly which assembled program it's loading (typically
        -- forwarded straight through from cpu.vhd's own ProgramData
        -- generic, which a testbench supplies -- see cpu_tb.vhd).
        ProgramData : STD_LOGIC_VECTOR (32767 downto 0)
    );
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
begin

    -- Asynchronous read: InstructionOut updates immediately whenever
    -- Address changes, with no clock involved at all -- matching a real
    -- ROM, which has no write port and therefore nothing to synchronise
    -- to. Uses a process (rather than a concurrent slice expression) purely
    -- so the address-to-integer conversion is a local variable computed
    -- once, then used to slice ProgramData -- VHDL-2008 allows a slice's
    -- bounds to be a dynamic (non-locally-static) expression as long as
    -- the slice's width (always 32 here) stays static, which this
    -- satisfies either way; the process form just reads more clearly than
    -- repeating the arithmetic twice in one expression. ProgramData is a
    -- generic (elaboration-time constant), not a signal, so it does not
    -- need to appear in this process's sensitivity list.
    ReadPort: process (Address)
        variable AddressIndex : integer;
    begin
        AddressIndex := to_integer(unsigned(Address));
        InstructionOut <= ProgramData((AddressIndex + 1) * 32 - 1 downto AddressIndex * 32);
    end process;

end Behavioral;
