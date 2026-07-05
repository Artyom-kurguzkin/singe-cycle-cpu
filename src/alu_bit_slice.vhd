library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ALUBitSlice is
    Port (
        Opcode    : in  STD_LOGIC_VECTOR ( 2 downto 0 );
        InputA    : in  STD_LOGIC;
        InputB    : in  STD_LOGIC;
        CarryIn   : in  STD_LOGIC;
        Output    : out STD_LOGIC;
        CarryOut  : out STD_LOGIC
    );
end ALUBitSlice;

architecture Behavioral of ALUBitSlice is
begin
    process ( Opcode, InputA, InputB, CarryIn )
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

            when "101" => -- NOT A
                Output <= not InputA;

            when "110" => -- Left Bit Shift passthrough (shift wiring done by the caller)
                Output   <= InputA;
                CarryOut <= InputB;

            when "111" => -- A++
                result   := ( '0' & InputA ) + ( '0' & CarryIn );
                Output   <= result ( 0 );
                CarryOut <= result ( 1 );

            when others =>
                Output <= '0';
        end case;

    end process;
end Behavioral;
