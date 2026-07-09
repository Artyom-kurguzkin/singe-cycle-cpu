library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- 1-bit ALU slice: computes one bit of add/sub/and/or/xor/not/lbs/inc.
-- Alu32 chains 32 of these, CarryIn to CarryOut, into a ripple-carry ALU.
entity ALUBitSlice is
    Port (
        -- Shared operation for every bit in the chain this cycle.
        Opcode    : in  STD_LOGIC_VECTOR ( 2 downto 0 );

        -- Operand bits at this position.
        InputA    : in  STD_LOGIC;
        InputB    : in  STD_LOGIC;

        -- Carry from bit i-1; ignored by logic/shift opcodes.
        CarryIn   : in  STD_LOGIC;

        Output    : out STD_LOGIC;

        -- Carry to bit i+1 for arithmetic ops; for lbs, relays InputB
        -- straight through instead (see the "110" case below).
        CarryOut  : out STD_LOGIC
    );
end ALUBitSlice;

architecture Behavioral of ALUBitSlice is
begin
    -- Combinational: re-evaluates instantly on any input change.
    process ( Opcode, InputA, InputB, CarryIn )
        -- 2 bits wide: InputA + InputB + CarryIn can reach 3 ("11").
        variable result : unsigned ( 1 downto 0 );
    begin
        Output   <= '0';
        CarryOut <= '0';
        result   := ( others => '0' );

        case Opcode is
            when "000" => -- A + B
                result   := ( '0' & InputA ) + ( '0' & InputB ) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            -- A - B, via A + (NOT B) + CarryIn (two's-complement sub).
            -- Alu32 seeds CarryIn=1 for this opcode to supply the "+1".
            when "001" => -- A - B
                result   := ( '0' & InputA ) + ( '0' & (not InputB)) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            when "010" => -- A AND B
                Output <= InputA and InputB;

            when "011" => -- A OR B
                Output <= InputA or InputB;

            when "100" => -- A XOR B
                Output <= InputA xor InputB;

            when "101" => -- NOT A (InputB unused)
                Output <= not InputA;

            -- lbs: a single slice can't shift by itself. This slice just
            -- passes InputA through; Alu32 feeds bit i-1's value into
            -- InputA to actually produce the shift.
            when "110" =>
                Output   <= InputA;
                CarryOut <= InputB;

            -- A + 1. Same adder as "add" with InputB dropped; Alu32 seeds
            -- CarryIn=1 to supply the "+1".
            when "111" => -- A++
                result   := ( '0' & InputA ) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            -- Unreachable (Opcode's 3 bits cover 000-111), but VHDL
            -- requires an exhaustive case over STD_LOGIC.
            when others =>
                Output <= '0';
        end case;

    end process;
end Behavioral;
