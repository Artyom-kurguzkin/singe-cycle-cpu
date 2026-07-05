library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for InstructionMemory. Since this is a plain ROM with
-- no write port, there is nothing to test except "does reading a given
-- address return exactly what's stored there" -- this spot-checks a few of
-- the hand-assembled test program's known addresses (see
-- instruction_memory.vhd for the full program and cpu_tb.vhd for the test
-- that actually exercises it end-to-end) plus one address that was
-- deliberately left to the "others => NopInstruction" default, to prove
-- that fallback actually applies to in-range addresses that weren't
-- explicitly listed.
entity InstructionMemory_tb is
end InstructionMemory_tb;

architecture Behavioral of InstructionMemory_tb is

    -- Re-declare the unit under test's interface so this testbench can
    -- instantiate it below.
    component InstructionMemory is
        Port (
            Address        : in  STD_LOGIC_VECTOR (9 downto 0);
            InstructionOut : out STD_LOGIC_VECTOR (31 downto 0)
        );
    end component;

    signal Address        : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal InstructionOut : STD_LOGIC_VECTOR (31 downto 0);

begin

    -- Instantiate the actual unit under test, wiring it to the signals
    -- above so the stimulus process can drive Address and check
    -- InstructionOut.
    UnitUnderTest: InstructionMemory
        port map (
            Address        => Address,
            InstructionOut => InstructionOut
        );

    Stimulus: process
    begin
        -- ---- Address 0: load immediate r0, 0 ----
        Address <= std_logic_vector(to_unsigned(0, 10));
        wait for 10 ns; -- let the async read settle
        assert InstructionOut = x"88000000"
            report "ADDRESS 0 FAILED" severity failure;

        -- ---- Address 3: add r1, r2, r3 ----
        Address <= std_logic_vector(to_unsigned(3, 10));
        wait for 10 ns;
        assert InstructionOut = x"0048C000"
            report "ADDRESS 3 FAILED" severity failure;

        -- ---- Address 16: jump 20 ----
        Address <= std_logic_vector(to_unsigned(16, 10));
        wait for 10 ns;
        assert InstructionOut = x"08140000"
            report "ADDRESS 16 FAILED" severity failure;

        -- ---- Address 31 (last instruction of the program: self-jump) ----
        Address <= std_logic_vector(to_unsigned(31, 10));
        wait for 10 ns;
        assert InstructionOut = x"081F0000"
            report "ADDRESS 31 (LAST INSTRUCTION) FAILED" severity failure;

        -- ---- Address 500 (an unlisted address) ----
        -- Well past the 32-instruction program, so this must fall through
        -- to the "others => NopInstruction" default.
        Address <= std_logic_vector(to_unsigned(500, 10));
        wait for 10 ns;
        assert InstructionOut = x"FC000000"
            report "UNLISTED ADDRESS DID NOT DEFAULT TO NOP" severity failure;

        -- ---- Address 1023 (top of the address range) ----
        -- Proves the full 1024-word range is wired up correctly, not just
        -- the addresses the program actually occupies.
        Address <= std_logic_vector(to_unsigned(1023, 10));
        wait for 10 ns;
        assert InstructionOut = x"FC000000"
            report "ADDRESS 1023 (TOP OF RANGE) FAILED" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
