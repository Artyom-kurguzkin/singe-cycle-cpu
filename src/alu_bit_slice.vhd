library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- ALUBitSlice is the fundamental building block of the whole ALU: it is a
-- 1-bit-wide ALU that can perform one bit's worth of every instruction the
-- ISA needs (add/sub/and/or/xor/not/lbs/inc). The 32-bit ALU (see alu32.vhd)
-- is built by instantiating 32 of these side by side and chaining CarryIn
-- to CarryOut, exactly like a ripple-carry adder is built from 1-bit full
-- adders. Doing it this way (instead of writing one big 32-bit process) is
-- the standard bit-slice ALU design technique taught in this course
-- (Practical 2) and keeps every opcode's logic in exactly one place.
entity ALUBitSlice is
    Port (
        -- Which operation this bit should perform this cycle. Shared by
        -- every bit in the 32-bit chain (all 32 slices always do the same
        -- operation in the same cycle).
        Opcode    : in  STD_LOGIC_VECTOR ( 2 downto 0 );

        -- The two operand bits at this bit position (bit i of OperandA/B
        -- when instantiated in alu32.vhd).
        InputA    : in  STD_LOGIC;
        InputB    : in  STD_LOGIC;

        -- Carry in from the next-less-significant bit slice (bit i-1). Only
        -- meaningful for the arithmetic opcodes (add/sub/inc); ignored by
        -- the logic opcodes (and/or/xor/not) and by the shift opcode.
        CarryIn   : in  STD_LOGIC;

        -- The computed result bit for this position.
        Output    : out STD_LOGIC;

        -- Carry out to the next-more-significant bit slice (bit i+1) for
        -- arithmetic ops. For the shift opcode this is repurposed to relay
        -- InputB straight through (see the "110" case below) rather than
        -- carrying an arithmetic carry.
        CarryOut  : out STD_LOGIC
    );
end ALUBitSlice;

architecture Behavioral of ALUBitSlice is
begin
    -- Combinational (not clocked) process: re-evaluates instantly whenever
    -- any input changes, which is what makes this a plain ALU rather than a
    -- clocked/latched circuit. This matches a single-cycle CPU, where the
    -- ALU's result must be ready within the same clock cycle it's asked to
    -- compute, with no extra cycle of delay.
    process ( Opcode, InputA, InputB, CarryIn )
        -- Scratch variable used for the arithmetic opcodes. It is 2 bits
        -- wide, not 1, because adding three 1-bit values (InputA + InputB +
        -- CarryIn) can produce a result as large as 3 (binary "11"), so we
        -- need the extra bit to hold the carry-out.
        variable result : unsigned ( 1 downto 0 );
    begin
        -- Default outputs so every signal is always driven (VHDL processes
        -- must assign every output on every path, or synthesis would infer
        -- an unwanted latch). These get overwritten below for whichever
        -- opcode actually matches.
        Output   <= '0';
        CarryOut <= '0';
        result   := ( others => '0' );

        case Opcode is
            -- add: full-adder equation. Concatenating a '0' in front of
            -- each 1-bit input turns them into 2-bit unsigned values so
            -- ordinary "+" produces a 2-bit sum whose top bit is the carry.
            when "000" => -- A + B
                result   := ( '0' & InputA ) + ( '0' & InputB ) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            -- sub: computed as A + (NOT B) + CarryIn, which is two's-
            -- complement subtraction (A - B = A + (~B + 1)). alu32.vhd
            -- seeds the very first CarryIn ('CarryChain(0)') to '1' for
            -- this opcode so the "+1" of two's complement happens
            -- automatically as part of the addition chain, rather than
            -- needing a separate increment step.
            when "001" => -- A - B
                result   := ( '0' & InputA ) + ( '0' & (not InputB)) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            -- Bitwise logic ops: these don't touch the carry chain at all
            -- (CarryOut stays at its default '0') since they operate on
            -- each bit completely independently, unlike addition/
            -- subtraction where each bit's result depends on the bit below
            -- it.
            when "010" => -- A AND B
                Output <= InputA and InputB;

            when "011" => -- A OR B
                Output <= InputA or InputB;

            when "100" => -- A XOR B
                Output <= InputA xor InputB;

            when "101" => -- NOT A (InputB is a don't-care for this opcode)
                Output <= not InputA;

            -- lbs (left bit shift): a single bit slice cannot shift a
            -- multi-bit value by itself — shifting means moving values
            -- *between* bit positions, which only the module wiring these
            -- slices together (alu32.vhd) can do. This slice just passes
            -- InputA straight through as Output. It's alu32.vhd's job to
            -- feed a *different* bit of OperandA into InputA specifically
            -- for this opcode (bit i-1 instead of bit i) so that the
            -- 32-bit result actually ends up shifted. CarryOut <= InputB
            -- here has no functional effect on any other slice's Output
            -- (case "110" ignores CarryIn entirely) — it just relays
            -- InputB outward in case a caller wants to observe it.
            when "110" => -- Left Bit Shift passthrough (shift wiring done by the caller)
                Output   <= InputA;
                CarryOut <= InputB;

            -- inc: A + 1. Reuses the same full-adder equation as "add" but
            -- with InputB dropped from the sum. Getting the "+1" requires
            -- CarryIn to be seeded to '1' by the caller (alu32.vhd does
            -- this the same way it does for "sub" above) — this slice on
            -- its own just adds whatever CarryIn it's given.
            when "111" => -- A++
                result   := ( '0' & InputA ) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            -- Any opcode value outside 000-111 can't occur (Opcode is only
            -- 3 bits wide, so every possible value is already covered
            -- above) but VHDL case statements over std_logic require an
            -- exhaustive "when others" to compile, since std_logic has
            -- extra values like 'U'/'X'/'Z' beyond '0'/'1'.
            when others =>
                Output <= '0';
        end case;

    end process;
end Behavioral;
