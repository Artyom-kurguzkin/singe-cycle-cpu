library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity alu is
    Port (
        a              : in  STD_LOGIC_VECTOR (3 downto 0);
        b              : in  STD_LOGIC_VECTOR (3 downto 0);
        s              : out STD_LOGIC_VECTOR (3 downto 0);
        OpCode         : in  STD_LOGIC_VECTOR (2 downto 0);
        zero           : out STD_LOGIC;
        overflow       : out STD_LOGIC;
        compl_overflow : out STD_LOGIC
    );
end alu;

architecture Behavioral of alu is

    component ALUBitSlice is
        Port (
            Opcode   : in  STD_LOGIC_VECTOR (2 downto 0);
            InputA   : in  STD_LOGIC;
            InputB   : in  STD_LOGIC;
            CarryIn  : in  STD_LOGIC;
            Output   : out STD_LOGIC;
            CarryOut : out STD_LOGIC
        );
    end component;

    signal carry : STD_LOGIC_VECTOR (4 downto 0);
    signal s_int : STD_LOGIC_VECTOR (3 downto 0);

begin
    -- Subtraction uses two's complement (A + ~B + 1), so seed carry-in with 1
    carry(0) <= '1' when (OpCode = "001" or OpCode = "111") else '0';

    bit0: ALUBitSlice port map (Opcode => OpCode, InputA => a(0), InputB => b(0), CarryIn => carry(0), Output => s_int(0), CarryOut => carry(1));
    bit1: ALUBitSlice port map (Opcode => OpCode, InputA => a(1), InputB => b(1), CarryIn => carry(1), Output => s_int(1), CarryOut => carry(2));
    bit2: ALUBitSlice port map (Opcode => OpCode, InputA => a(2), InputB => b(2), CarryIn => carry(2), Output => s_int(2), CarryOut => carry(3));
    bit3: ALUBitSlice port map (Opcode => OpCode, InputA => a(3), InputB => b(3), CarryIn => carry(3), Output => s_int(3), CarryOut => carry(4));

    s    <= s_int;
    zero <= '1' when s_int = "0000" else '0';

    -- Unsigned overflow: carry out of MSB
    overflow <= carry(4);

    -- Signed overflow: carry into MSB differs from carry out of MSB
    compl_overflow <= carry(3) xor carry(4);

end Behavioral;
