library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Directed testbench for ALUBitSlice in isolation, one small case per
-- opcode. This exercises the bit slice on its own (a single bit's worth of
-- each operation) before it gets trusted to be chained 32 times inside
-- Alu32 -- if a bug were introduced here, alu32_tb.vhd's word-level tests
-- would be much harder to root-cause.
entity AluBitSlice_tb is
end AluBitSlice_tb;

architecture Behavioral of AluBitSlice_tb is

    -- Re-declare the unit under test's interface so this testbench can
    -- instantiate it below.
    component ALUBitSlice is
        Port (
            Opcode   : in  STD_LOGIC_VECTOR(2 downto 0);
            InputA   : in  STD_LOGIC;
            InputB   : in  STD_LOGIC;
            CarryIn  : in  STD_LOGIC;
            Output   : out STD_LOGIC;
            CarryOut : out STD_LOGIC
        );
    end component;

    -- Signals that drive/observe the unit under test. The inputs need
    -- initial values because they are driven by the "apply" procedure
    -- below rather than by a clock, and simulation needs a defined starting
    -- state at time 0.
    signal Opcode   : STD_LOGIC_VECTOR(2 downto 0) := "000";
    signal InputA   : STD_LOGIC := '0';
    signal InputB   : STD_LOGIC := '0';
    signal CarryIn  : STD_LOGIC := '0';
    signal Output   : STD_LOGIC;
    signal CarryOut : STD_LOGIC;

    -- Small helper that drives one set of inputs and then waits long enough
    -- for the (combinational) ALUBitSlice to settle before the caller
    -- checks the outputs with an assertion. Using a procedure instead of
    -- repeating "signal <= value; wait for 20 ns;" before every assertion
    -- keeps each test case below to one readable line.
    procedure apply(
        signal op  : out STD_LOGIC_VECTOR(2 downto 0);
        signal a   : out STD_LOGIC;
        signal b   : out STD_LOGIC;
        signal cin : out STD_LOGIC;
        op_val  : in STD_LOGIC_VECTOR(2 downto 0);
        a_val   : in STD_LOGIC;
        b_val   : in STD_LOGIC;
        cin_val : in STD_LOGIC
    ) is
    begin
        op  <= op_val;
        a   <= a_val;
        b   <= b_val;
        cin <= cin_val;
        wait for 20 ns;
    end procedure;

begin

    -- Instantiate the actual unit under test, wiring it to the signals
    -- above so the stimulus process can drive it and check its outputs.
    uut: ALUBitSlice
        port map (
            Opcode   => Opcode,
            InputA   => InputA,
            InputB   => InputB,
            CarryIn  => CarryIn,
            Output   => Output,
            CarryOut => CarryOut
        );

    -- The actual test sequence: for every opcode, apply a handful of
    -- representative 1-bit inputs and assert the expected Output/CarryOut.
    -- Every assertion uses "severity failure" (never "error" or "warning")
    -- because only "failure" actually halts the simulation and makes
    -- `ghdl -r` return a non-zero exit code on a failing check -- see
    -- docs/cpu-implementation-plan.md section 4 for why this matters (a
    -- failing assertion at a lower severity would print a message but let
    -- the simulation carry on to print "All tests passed." regardless).
    stimulus: process
    begin

        -- ---- Opcode 000: Addition (A + B + Cin) ----
        -- 0+0+0 = 0, carry 0
        apply(Opcode, InputA, InputB, CarryIn, "000", '0', '0', '0');
        assert Output = '0' and CarryOut = '0' report "ADD 0+0+0 FAILED" severity failure;

        -- 1+0+0 = 1, carry 0
        apply(Opcode, InputA, InputB, CarryIn, "000", '1', '0', '0');
        assert Output = '1' and CarryOut = '0' report "ADD 1+0+0 FAILED" severity failure;

        -- 1+1+0 = 0, carry 1 (this is the case that actually exercises the
        -- carry-out logic: two 1-bits alone overflow a single bit)
        apply(Opcode, InputA, InputB, CarryIn, "000", '1', '1', '0');
        assert Output = '0' and CarryOut = '1' report "ADD 1+1+0 FAILED" severity failure;

        -- 1+1+1 = 1, carry 1 (all three inputs to the full adder set)
        apply(Opcode, InputA, InputB, CarryIn, "000", '1', '1', '1');
        assert Output = '1' and CarryOut = '1' report "ADD 1+1+1 FAILED" severity failure;

        -- ---- Opcode 001: Subtraction (A - B via A + NOT(B) + Cin) ----
        -- 1-0: A=1, B=0 -> A+NOT(B)+Cin = 1+1+0 = 0 carry 1
        apply(Opcode, InputA, InputB, CarryIn, "001", '1', '0', '0');
        assert Output = '0' and CarryOut = '1' report "SUB 1-0 FAILED" severity failure;

        -- 1-1: A=1, B=1 -> 1+0+0 = 1 carry 0
        apply(Opcode, InputA, InputB, CarryIn, "001", '1', '1', '0');
        assert Output = '1' and CarryOut = '0' report "SUB 1-1 FAILED" severity failure;

        -- ---- Opcode 010: AND ----
        -- All four truth-table rows aren't strictly necessary (AND is
        -- symmetric), but 0,0 / 1,0 / 1,1 covers both "false" combinations
        -- and the one "true" combination.
        apply(Opcode, InputA, InputB, CarryIn, "010", '0', '0', '0');
        assert Output = '0' report "AND 0,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "010", '1', '0', '0');
        assert Output = '0' report "AND 1,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "010", '1', '1', '0');
        assert Output = '1' report "AND 1,1 FAILED" severity failure;

        -- ---- Opcode 011: OR ----
        apply(Opcode, InputA, InputB, CarryIn, "011", '0', '0', '0');
        assert Output = '0' report "OR 0,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "011", '1', '0', '0');
        assert Output = '1' report "OR 1,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "011", '0', '1', '0');
        assert Output = '1' report "OR 0,1 FAILED" severity failure;

        -- ---- Opcode 100: XOR ----
        apply(Opcode, InputA, InputB, CarryIn, "100", '0', '0', '0');
        assert Output = '0' report "XOR 0,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "100", '1', '0', '0');
        assert Output = '1' report "XOR 1,0 FAILED" severity failure;

        -- Two equal bits XOR to 0 -- distinct from AND's "1,1 -> 1", worth
        -- checking explicitly so a copy-paste bug between XOR and OR/AND
        -- would be caught.
        apply(Opcode, InputA, InputB, CarryIn, "100", '1', '1', '0');
        assert Output = '0' report "XOR 1,1 FAILED" severity failure;

        -- ---- Opcode 101: NOT A (InputB is a don't-care for this opcode) ----
        apply(Opcode, InputA, InputB, CarryIn, "101", '0', '0', '0');
        assert Output = '1' report "NOT 0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "101", '1', '0', '0');
        assert Output = '0' report "NOT 1 FAILED" severity failure;

        -- ---- Opcode 110: Left Bit Shift passthrough ----
        -- At the single-bit-slice level this opcode is *not* an actual
        -- shift (a lone bit can't move itself to another position) -- it's
        -- Output = InputA, CarryOut = InputB. The real shifting happens one
        -- level up, in alu32.vhd, which feeds a different bit of the
        -- 32-bit operand into each slice's InputA for this opcode. See
        -- alu32_tb.vhd for the test that actually verifies shifting.
        apply(Opcode, InputA, InputB, CarryIn, "110", '1', '0', '0');
        assert Output = '1' and CarryOut = '0' report "LBS A=1,B=0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "110", '0', '1', '0');
        assert Output = '0' and CarryOut = '1' report "LBS A=0,B=1 FAILED" severity failure;

        -- ---- Opcode 111: Increment (A + 1) ----
        -- inc computes A + CarryIn, so the caller must seed CarryIn='1' to
        -- get "+1" out of it (this is exactly what alu32.vhd's
        -- CarryChain(0) seeding does for real usage -- see alu32.vhd). This
        -- testbench seeds CarryIn='1' directly on the "apply" calls below
        -- to exercise the slice the same way alu32.vhd actually uses it.
        -- 0+1 = 1, carry 0
        apply(Opcode, InputA, InputB, CarryIn, "111", '0', '0', '1');
        assert Output = '1' and CarryOut = '0' report "INC 0 FAILED" severity failure;

        -- 1+1 = 0, carry 1 (this bit overflows, same as the ADD 1+1+0 case
        -- above, just reached via the inc opcode instead)
        apply(Opcode, InputA, InputB, CarryIn, "111", '1', '0', '1');
        assert Output = '0' and CarryOut = '1' report "INC 1 FAILED" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
