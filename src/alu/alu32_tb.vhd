library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for the full 32-bit Alu32, one representative case per
-- opcode plus a couple of full-width edge cases. Where AluBitSlice_tb.vhd
-- checks each operation one bit at a time, this file checks that the 32
-- chained bit slices actually behave correctly as a whole word -- in
-- particular that carries propagate all the way across the 32-bit chain
-- (the wraparound cases below) and that the lbs opcode's special wiring in
-- alu32.vhd genuinely shifts a multi-bit value rather than doing nothing.
entity alu32_tb is
end alu32_tb;

architecture Behavioral of alu32_tb is

    -- Re-declare the unit under test's interface so this testbench can
    -- instantiate it below.
    component Alu32 is
        Port (
            OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
            OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
            OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
            Result   : out STD_LOGIC_VECTOR (31 downto 0);
            ZeroFlag : out STD_LOGIC
        );
    end component;

    -- Signals that drive/observe the unit under test, initialised to a
    -- defined state at time 0 since nothing else (no clock) would
    -- otherwise give them a starting value.
    signal OperandA : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal OperandB : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal OpCode   : STD_LOGIC_VECTOR (2 downto 0)  := "000";
    signal Result   : STD_LOGIC_VECTOR (31 downto 0);
    signal ZeroFlag : STD_LOGIC;

    -- Helper that drives one full test vector (opcode + both 32-bit
    -- operands) and waits for the combinational Alu32 to settle before the
    -- caller inspects Result/ZeroFlag. Keeps every test case below to one
    -- readable call instead of three separate signal assignments plus a
    -- wait statement.
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

    -- Instantiate the actual unit under test, wiring it to the signals
    -- above so the stimulus process can drive it and check its outputs.
    UnitUnderTest: Alu32
        port map (
            OperandA => OperandA,
            OperandB => OperandB,
            OpCode   => OpCode,
            Result   => Result,
            ZeroFlag => ZeroFlag
        );

    -- Every assertion below uses "severity failure" (never "error" or
    -- "warning"), matching the convention established in
    -- alu_bit_slice_tb.vhd / docs/cpu-implementation-plan.md section 4, so
    -- a failing check actually stops the simulation and fails `make sim`
    -- instead of just printing a message that a later "All tests passed."
    -- could paper over.
    Stimulus: process
    begin

        -- ---- OpCode 000: Addition ----
        -- 5 + 7 = 12: an ordinary case with no carry propagation of note.
        apply(OpCode, OperandA, OperandB, "000",
              STD_LOGIC_VECTOR(to_unsigned(5, 32)),
              STD_LOGIC_VECTOR(to_unsigned(7, 32)));
        assert unsigned(Result) = 12 and ZeroFlag = '0'
            report "ADD 5+7 FAILED" severity failure;

        -- Full-width carry propagation: 0xFFFFFFFF + 1 wraps to 0. This is
        -- the case that actually proves the carry chain threads correctly
        -- through all 32 chained ALUBitSlice instances -- every single bit
        -- must carry into the next for the result to come out as exactly
        -- zero instead of some partially-wrong value.
        apply(OpCode, OperandA, OperandB, "000", x"FFFFFFFF",
              STD_LOGIC_VECTOR(to_unsigned(1, 32)));
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "ADD wraparound FAILED" severity failure;

        -- ---- OpCode 001: Subtraction ----
        -- 10 - 3 = 7: an ordinary case exercising the two's-complement
        -- (A + NOT(B) + 1) subtraction path.
        apply(OpCode, OperandA, OperandB, "001",
              STD_LOGIC_VECTOR(to_unsigned(10, 32)),
              STD_LOGIC_VECTOR(to_unsigned(3, 32)));
        assert unsigned(Result) = 7 and ZeroFlag = '0'
            report "SUB 10-3 FAILED" severity failure;

        -- 5 - 5 = 0: this is exactly the pattern beq/bne rely on in the
        -- real CPU (equal operands subtract to zero), so it is worth
        -- checking ZeroFlag here specifically, not just Result.
        apply(OpCode, OperandA, OperandB, "001",
              STD_LOGIC_VECTOR(to_unsigned(5, 32)),
              STD_LOGIC_VECTOR(to_unsigned(5, 32)));
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "SUB 5-5 FAILED" severity failure;

        -- ---- OpCode 010: AND ----
        -- Alternating nibble patterns so every bit position gets both a
        -- 0-and-1 and a 1-and-1 combination in a single test vector.
        apply(OpCode, OperandA, OperandB, "010", x"FF00FF00", x"0F0F0F0F");
        assert Result = x"0F000F00"
            report "AND FAILED" severity failure;

        -- ---- OpCode 011: OR ----
        -- Complementary nibble patterns that OR together to all-ones,
        -- which would only happen if every single bit position computed OR
        -- correctly.
        apply(OpCode, OperandA, OperandB, "011", x"F0F0F0F0", x"0F0F0F0F");
        assert Result = x"FFFFFFFF"
            report "OR FAILED" severity failure;

        -- ---- OpCode 100: XOR ----
        -- Alternating-bit operands that are exact complements of each
        -- other, so XOR-ing them should also produce all-ones.
        apply(OpCode, OperandA, OperandB, "100", x"AAAAAAAA", x"55555555");
        assert Result = x"FFFFFFFF"
            report "XOR FAILED" severity failure;

        -- ---- OpCode 101: NOT A (OperandB is a don't-care for this opcode) ----
        apply(OpCode, OperandA, OperandB, "101", x"00000000", x"00000000");
        assert Result = x"FFFFFFFF"
            report "NOT FAILED" severity failure;

        -- ---- OpCode 110: LBS (left shift by 1, zero-filled at bit 0) ----
        -- 0xDEADBEEF << 1 = 0xBD5B7DDE (verified independently in binary:
        -- 0xDEADBEEF's top bit is dropped, every other bit moves up one
        -- position, and a 0 fills in at the bottom). This is the important
        -- regression test for the alu32.vhd shift-wiring fix -- if
        -- alu32.vhd went back to naively wiring OperandA(i) -> InputA(i)
        -- for every opcode (as a first, buggy draft did), this assertion
        -- would fail because Result would just equal OperandA unchanged.
        apply(OpCode, OperandA, OperandB, "110", x"DEADBEEF", x"00000000");
        assert Result = x"BD5B7DDE"
            report "LBS FAILED" severity failure;

        -- Shift-out of the MSB is discarded: 0x80000000 << 1 = 0. Only bit
        -- 31 is set beforehand, and a left shift moves it out of the
        -- 32-bit result entirely (there is nowhere for it to go), so the
        -- correct result is all zero bits.
        apply(OpCode, OperandA, OperandB, "110", x"80000000", x"00000000");
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "LBS MSB discard FAILED" severity failure;

        -- ---- OpCode 111: Increment (A + 1, carry-in seeded by Alu32) ----
        -- 41 + 1 = 42: an ordinary case with no carry propagation of note.
        apply(OpCode, OperandA, OperandB, "111",
              STD_LOGIC_VECTOR(to_unsigned(41, 32)),
              x"00000000");
        assert unsigned(Result) = 42 and ZeroFlag = '0'
            report "INC 41 FAILED" severity failure;

        -- Full-width carry propagation, same idea as the ADD wraparound
        -- case above but reached via inc's own CarryChain(0) seeding
        -- instead of add's: 0xFFFFFFFF + 1 wraps to 0.
        apply(OpCode, OperandA, OperandB, "111", x"FFFFFFFF", x"00000000");
        assert unsigned(Result) = 0 and ZeroFlag = '1'
            report "INC wraparound FAILED" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
