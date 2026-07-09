library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for Alu32, one representative case per opcode plus
-- full-width edge cases: proves carries propagate across all 32 chained
-- bit slices, and that lbs's shift wiring actually shifts.
entity alu32_tb is
end alu32_tb;

architecture Behavioral of alu32_tb is

    component Alu32 is
        Port (
            OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
            OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
            OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
            Result   : out STD_LOGIC_VECTOR (31 downto 0);
            ZeroFlag : out STD_LOGIC
        );
    end component;

    signal OperandA : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal OperandB : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal OpCode   : STD_LOGIC_VECTOR (2 downto 0)  := "000";
    signal Result   : STD_LOGIC_VECTOR (31 downto 0);
    signal ZeroFlag : STD_LOGIC;

    -- Drives one test vector and waits for the combinational ALU to settle.
    procedure apply(
        signal OpCodeSignal   : out STD_LOGIC_VECTOR (2 downto 0);
        signal OperandASignal : out STD_LOGIC_VECTOR (31 downto 0);
        signal OperandBSignal : out STD_LOGIC_VECTOR (31 downto 0);
        OpCodeValue           : in STD_LOGIC_VECTOR (2 downto 0);
        OperandAValue         : in STD_LOGIC_VECTOR (31 downto 0);
        OperandBValue         : in STD_LOGIC_VECTOR (31 downto 0)
    ) is
    begin
        OpCodeSignal   <= OpCodeValue;
        OperandASignal <= OperandAValue;
        OperandBSignal <= OperandBValue;
        wait for 20 ns;
    end procedure;

begin

    UnitUnderTest: Alu32
        port map (
            OperandA => OperandA,
            OperandB => OperandB,
            OpCode   => OpCode,
            Result   => Result,
            ZeroFlag => ZeroFlag
        );

    Stimulus: process
    begin

        -- ---- 000: Add ----
        apply(OpCode, OperandA, OperandB, "000",
              STD_LOGIC_VECTOR(to_unsigned(5, 32)),
              STD_LOGIC_VECTOR(to_unsigned(7, 32)));
        assert unsigned(Result) = 12 and ZeroFlag = '0'
            report "ADD 5+7 FAILED" severity failure;

        -- Full-width carry propagation: 0xFFFFFFFF + 1 wraps to 0.
        apply(OpCode, OperandA, OperandB, "000", x"FFFFFFFF",
              STD_LOGIC_VECTOR(to_unsigned(1, 32)));
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "ADD wraparound FAILED" severity failure;

        -- ---- 001: Subtract ----
        apply(OpCode, OperandA, OperandB, "001",
              STD_LOGIC_VECTOR(to_unsigned(10, 32)),
              STD_LOGIC_VECTOR(to_unsigned(3, 32)));
        assert unsigned(Result) = 7 and ZeroFlag = '0'
            report "SUB 10-3 FAILED" severity failure;

        -- Equal operands subtract to zero -- the pattern beq/bne rely on.
        apply(OpCode, OperandA, OperandB, "001",
              STD_LOGIC_VECTOR(to_unsigned(5, 32)),
              STD_LOGIC_VECTOR(to_unsigned(5, 32)));
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "SUB 5-5 FAILED" severity failure;

        -- ---- 010: AND ----
        apply(OpCode, OperandA, OperandB, "010", x"FF00FF00", x"0F0F0F0F");
        assert Result = x"0F000F00"
            report "AND FAILED" severity failure;

        -- ---- 011: OR ----
        apply(OpCode, OperandA, OperandB, "011", x"F0F0F0F0", x"0F0F0F0F");
        assert Result = x"FFFFFFFF"
            report "OR FAILED" severity failure;

        -- ---- 100: XOR ----
        apply(OpCode, OperandA, OperandB, "100", x"AAAAAAAA", x"55555555");
        assert Result = x"FFFFFFFF"
            report "XOR FAILED" severity failure;

        -- ---- 101: NOT A (OperandB don't-care) ----
        apply(OpCode, OperandA, OperandB, "101", x"00000000", x"00000000");
        assert Result = x"FFFFFFFF"
            report "NOT FAILED" severity failure;

        -- ---- 110: LBS (left shift by 1, zero-filled at bit 0) ----
        -- 0xDEADBEEF << 1 = 0xBD5B7DDE.
        apply(OpCode, OperandA, OperandB, "110", x"DEADBEEF", x"00000000");
        assert Result = x"BD5B7DDE"
            report "LBS FAILED" severity failure;

        -- MSB shifts out and is discarded: 0x80000000 << 1 = 0.
        apply(OpCode, OperandA, OperandB, "110", x"80000000", x"00000000");
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "LBS MSB discard FAILED" severity failure;

        -- ---- 111: Increment ----
        apply(OpCode, OperandA, OperandB, "111",
              STD_LOGIC_VECTOR(to_unsigned(41, 32)),
              x"00000000");
        assert unsigned(Result) = 42 and ZeroFlag = '0'
            report "INC 41 FAILED" severity failure;

        -- Full-width carry propagation via inc's own seeding.
        apply(OpCode, OperandA, OperandB, "111", x"FFFFFFFF", x"00000000");
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "INC wraparound FAILED" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
