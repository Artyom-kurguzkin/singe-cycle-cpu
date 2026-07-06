library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use STD.TEXTIO.ALL;

-- ProgramLoaderPkg is the "loading mechanism," and it is entirely a
-- testbench-side concern: hardware components in this project (Alu32,
-- RegisterFile, DataMemory, ControlUnit, PcUnit, InstructionMemory,
-- cpu.vhd) never call this, reference this package, or know it exists.
-- Reading a file is inherently non-synthesizable (there is no real-silicon
-- equivalent of STD.TEXTIO), so it has no business being wired into
-- anything meant to resemble real CPU hardware -- not even as an "internal
-- implementation detail" component. A real ROM's contents are fixed at
-- fabrication; the closest hardware-honest equivalent here is a generic,
-- resolved once at elaboration, which is exactly how
-- InstructionMemory/cpu.vhd receive their program (see those files'
-- ProgramData generic). This package is what a testbench (playing the role
-- of firmware/an OS loader deciding what to burn/flash in a real system)
-- calls to actually produce that generic's value.
--
-- A plain function is enough here -- no state, no ports, nothing to wire.
-- It only needs to live in a package (rather than being declared directly
-- inside one testbench) because VHDL requires any subprogram shared across
-- multiple separately-compiled files to be declared in a package, and
-- three testbenches already need to load a program: cpu_tb.vhd,
-- instruction_memory_tb.vhd, alu32_instruction_memory_integration_tb.vhd.
package ProgramLoaderPkg is

    -- Reads FilePath (resolved relative to the working directory `ghdl -r`
    -- is invoked from -- this project's Makefile always runs it from the
    -- repo root) -- a plain machine-code file, one instruction per line,
    -- each line exactly 32 characters of '0'/'1' (tools/assemble_sieve.py's
    -- --bits-out output) -- and returns a full 1024-word ROM image,
    -- flattened into a single 32768-bit vector (word W at bits
    -- ((W+1)*32-1) downto (W*32)), with every address past the end of the
    -- file filled with `nop`. "impure" because reading a file is a
    -- side-effecting operation, which VHDL requires functions to declare
    -- explicitly.
    impure function LoadProgramFromFile(FilePath : string) return STD_LOGIC_VECTOR;

end package ProgramLoaderPkg;

package body ProgramLoaderPkg is

    impure function LoadProgramFromFile(FilePath : string) return STD_LOGIC_VECTOR is
        file ProgramFile      : text open read_mode is FilePath;
        variable FileLine     : line;
        variable Program      : STD_LOGIC_VECTOR (32767 downto 0);
        variable WordIndex    : integer := 0;
        variable BitCharacter : character;
        variable Word         : STD_LOGIC_VECTOR (31 downto 0);

        -- nop's encoding (J-format, opcode 0x3f, address/unused fields
        -- irrelevant per the spec's instruction table): opcode occupies
        -- bits 31 downto 26, so 0x3f ("111111") shifted into that
        -- position, with every other bit zero, is 0xFC000000.
        constant NopInstruction : STD_LOGIC_VECTOR (31 downto 0) := x"FC000000";
    begin
        for FillIndex in 0 to 1023 loop
            Program((FillIndex + 1) * 32 - 1 downto FillIndex * 32) := NopInstruction;
        end loop;

        while not endfile(ProgramFile) and WordIndex < 1024 loop
            readline(ProgramFile, FileLine);
            for BitIndex in 0 to 31 loop
                read(FileLine, BitCharacter);
                if BitCharacter = '1' then
                    Word(31 - BitIndex) := '1';
                else
                    Word(31 - BitIndex) := '0';
                end if;
            end loop;
            Program((WordIndex + 1) * 32 - 1 downto WordIndex * 32) := Word;
            WordIndex := WordIndex + 1;
        end loop;

        return Program;
    end function;

end package body ProgramLoaderPkg;
