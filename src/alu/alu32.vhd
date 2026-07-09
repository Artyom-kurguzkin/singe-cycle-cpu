library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- 32-bit ALU: 32 chained ALUBitSlice instances forming a ripple-carry
-- adder. No per-operation logic lives here; each slice decides its own
-- bit's output from Opcode. This entity only fans operands/opcode out to
-- the slices, threads the carry chain, and derives ZeroFlag.
entity Alu32 is
    Port (
        OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
        OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
        OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
        Result   : out STD_LOGIC_VECTOR (31 downto 0);

        -- '1' when Result is all zero (used for rs = rt comparisons via
        -- subtraction). No overflow flag: nothing here needs one.
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

    -- CarryChain(i) = carry into slice i, CarryChain(i+1) = carry out of
    -- slice i. Bit 32 exists only because slice 31 needs somewhere to
    -- drive CarryOut. Zero-initialized to avoid 'U' at t=0.
    signal CarryChain          : STD_LOGIC_VECTOR (32 downto 0) := (others => '0');

    -- Output bits from the slices before they reach Result/ZeroFlag ("out"
    -- ports can't be read back inside the same entity).
    signal ResultInternal      : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

    -- OperandA shifted left by 1 (zero-filled at bit 0), for lbs: a single
    -- slice can't shift itself, so lbs feeds slice i's InputA from
    -- OperandA(i-1) instead of OperandA(i).
    signal OperandAShiftedLeft : STD_LOGIC_VECTOR (31 downto 0);

    -- InputA actually fed to the slices: shifted view for lbs, else OperandA.
    signal EffectiveOperandA   : STD_LOGIC_VECTOR (31 downto 0);

begin
    -- Seed carry-in: sub ("001") and inc ("111") both need CarryIn=1 to
    -- get "invert and add one" / "+1" out of the shared add logic in each
    -- slice; every other opcode starts at 0.
    CarryChain(0) <= '1' when (OpCode = "001" or OpCode = "111") else '0';

    OperandAShiftedLeft <= OperandA(30 downto 0) & '0';
    EffectiveOperandA   <= OperandAShiftedLeft when OpCode = "110" else OperandA;

    -- One ALUBitSlice per bit, 0 (LSB) to 31 (MSB), chained via CarryChain.
    BitSlices: for BitIndex in 0 to 31 generate
        BitSlice: ALUBitSlice
            port map (
                Opcode   => OpCode,
                InputA   => EffectiveOperandA(BitIndex),
                InputB   => OperandB(BitIndex),
                CarryIn  => CarryChain(BitIndex),
                Output   => ResultInternal(BitIndex),
                CarryOut => CarryChain(BitIndex + 1)
            );
    end generate;

    Result   <= ResultInternal;
    ZeroFlag <= '1' when ResultInternal = (ResultInternal'range => '0') else '0';

end Structural;
