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

    -- Program contents, used only until Step 9 assembles the real Sieve of
    -- Eratosthenes program from Appendix 3 (see
    -- docs/cpu-implementation-plan.md section 3/5). This is a real test
    -- program (superseding the earlier arbitrary 0x11111111-style
    -- placeholder from Step 4) exercising every instruction class
    -- cpu_tb.vhd needs to check: R-type arithmetic, load-immediate,
    -- store/load, a taken beq, a taken bne, a not-taken bne, and an
    -- absolute jump. Since cpu.vhd's only externally-visible ports are
    -- clk/ioaddress/iodata/ioenable (no debug ports, matching the spec
    -- exactly), the tail of the program stores every interesting register
    -- out to the memory-mapped IO range (128 and up) so cpu_tb.vhd can
    -- verify the whole run's outcome purely by observing those external
    -- ports -- the same technique the real sieve program uses to report
    -- primes, and exactly what cpu_sieve_tb.vhd (Step 10) will need
    -- anyway. The program ends in a self-jump ("steady-state loop", the
    -- same pattern Appendix 3 uses at its #label4) so the CPU settles at a
    -- fixed PC once finished, no matter how many extra clock cycles a
    -- testbench runs afterwards.
    --
    -- Source: tools/programs/cpu_test_program.asm. Assembled with:
    --   python3 tools/assemble_sieve.py tools/programs/cpu_test_program.asm \
    --       --binary-out tools/programs/cpu_test_program.listing.txt \
    --       --vhdl-out tools/programs/cpu_test_program.instructions.vhd
    -- (the constant below is that generated file's contents, pasted in
    -- directly -- not hand-transcribed, so there is no manual-bit-shifting
    -- transcription error possible here the way there would be by hand).
    -- tools/assemble_sieve.py's own comments explain the encoding rules,
    -- including the load/store operand-order asymmetry documented in
    -- docs/cpu-implementation-plan.md section 2.
    constant Instructions : InstructionArrayType := (
        0   => x"88000000", -- load immediate r0 0
        1   => x"88040028", -- load immediate r1 10
        2   => x"88080050", -- load immediate r2 20
        3   => x"0048C000", -- add r1 r2 r3
        4   => x"00C50800", -- sub r3 r1 r4
        5   => x"841000C8", -- store r0 r4 50
        6   => x"8C1400C8", -- load r5 r0 50
        7   => x"14440008", -- beq r1 r1 #beq_landing
        8   => x"88180134", -- load immediate r6 77
        9   => x"881C018C", -- load immediate r7 99
        10  => x"10480008", -- bne r1 r2 #bne_taken_landing
        11  => x"882001BC", -- load immediate r8 111
        12  => x"88240378", -- load immediate r9 222
        13  => x"10440008", -- bne r1 r1 2
        14  => x"88280534", -- load immediate r10 333
        15  => x"882C06F0", -- load immediate r11 444
        16  => x"08140000", -- jump #jump_landing
        17  => x"88340A68", -- load immediate r13 666
        18  => x"88340C24", -- load immediate r13 777
        19  => x"88340DE0", -- load immediate r13 888
        20  => x"883008AC", -- load immediate r12 555
        21  => x"840C0200", -- store r0 r3 128
        22  => x"84100204", -- store r0 r4 129
        23  => x"84140208", -- store r0 r5 130
        24  => x"8418020C", -- store r0 r6 131
        25  => x"841C0210", -- store r0 r7 132
        26  => x"84200214", -- store r0 r8 133
        27  => x"84240218", -- store r0 r9 134
        28  => x"8428021C", -- store r0 r10 135
        29  => x"84300220", -- store r0 r12 136
        30  => x"84340224", -- store r0 r13 137
        31  => x"081F0000", -- jump #steady_state_loop
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
