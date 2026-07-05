library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Alu32 is
    Port (
        OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
        OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
        OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
        Result   : out STD_LOGIC_VECTOR (31 downto 0);
        ZeroFlag : out STD_LOGIC
    );
end Alu32;

architecture Structural of Alu32 is

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

    signal CarryChain     : STD_LOGIC_VECTOR (32 downto 0);
    signal ResultInternal : STD_LOGIC_VECTOR (31 downto 0);

begin
    -- Subtraction uses two's complement (A + ~B + 1), so seed carry-in with 1
    CarryChain(0) <= '1' when (OpCode = "001" or OpCode = "111") else '0';

    BitSlices: for BitIndex in 0 to 31 generate
        BitSlice: ALUBitSlice
            port map (
                Opcode   => OpCode,
                InputA   => OperandA(BitIndex),
                InputB   => OperandB(BitIndex),
                CarryIn  => CarryChain(BitIndex),
                Output   => ResultInternal(BitIndex),
                CarryOut => CarryChain(BitIndex + 1)
            );
    end generate;11

    Result   <= ResultInternal;
    ZeroFlag <= '1' when ResultInternal = (ResultInternal'range => '0') else '0';

end Structural;
