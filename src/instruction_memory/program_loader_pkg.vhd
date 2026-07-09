library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use STD.TEXTIO.ALL;

-- Testbench-only loader: reads an assembled program file and builds the
-- flat ROM image InstructionMemory's ProgramData generic expects. File
-- I/O is non-synthesizable, so this never runs from real CPU hardware.
package ProgramLoaderPkg is

    -- Reads a plain-text machine-code file (one instruction per line, each
    -- line 32 characters of '0'/'1') and returns a 1024-word ROM image
    -- flattened into a 32768-bit vector (word W at bits
    -- ((W+1)*32-1) downto (W*32)); addresses past the file's end are
    -- filled with nop. "impure" because reading a file is a side effect.
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

        -- nop = J-format, opcode 0x3f in bits 31 downto 26, rest zero.
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
