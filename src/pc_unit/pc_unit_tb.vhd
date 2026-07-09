library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for PcUnit: sequential advance (including wraparound
-- at the top of the address range), a taken branch both directions
-- (forward and backward/looping), a not-taken branch (falls through), and
-- a jump (overrides everything else).
entity PcUnit_tb is
end PcUnit_tb;

architecture Behavioral of PcUnit_tb is

    component PcUnit is
        Port (
            CurrentProgramCounter : in  STD_LOGIC_VECTOR (9 downto 0);
            BranchEnable          : in  STD_LOGIC;
            BranchOnZero          : in  STD_LOGIC;
            ZeroFlag              : in  STD_LOGIC;
            JumpEnable            : in  STD_LOGIC;
            BranchImmediate       : in  STD_LOGIC_VECTOR (9 downto 0);
            JumpAddress           : in  STD_LOGIC_VECTOR (9 downto 0);
            NextProgramCounter    : out STD_LOGIC_VECTOR (9 downto 0)
        );
    end component;

    signal CurrentProgramCounter : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal BranchEnable          : STD_LOGIC := '0';
    signal BranchOnZero          : STD_LOGIC := '0';
    signal ZeroFlag              : STD_LOGIC := '0';
    signal JumpEnable            : STD_LOGIC := '0';
    signal BranchImmediate       : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal JumpAddress           : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal NextProgramCounter    : STD_LOGIC_VECTOR (9 downto 0);

begin

    UnitUnderTest: PcUnit
        port map (
            CurrentProgramCounter => CurrentProgramCounter,
            BranchEnable          => BranchEnable,
            BranchOnZero          => BranchOnZero,
            ZeroFlag              => ZeroFlag,
            JumpEnable            => JumpEnable,
            BranchImmediate       => BranchImmediate,
            JumpAddress           => JumpAddress,
            NextProgramCounter    => NextProgramCounter
        );

    Stimulus: process
    begin
        -- ---- Sequential advance: PC=10 -> 11, no branch/jump ----
        CurrentProgramCounter <= std_logic_vector(to_unsigned(10, 10));
        BranchEnable <= '0';
        JumpEnable   <= '0';
        wait for 10 ns; -- let the combinational logic settle
        assert unsigned(NextProgramCounter) = 11
            report "SEQUENTIAL ADVANCE FAILED" severity failure;

        -- ---- Sequential wraparound: PC=1023 (max) -> 0 ----
        -- Proves the +1 correctly wraps at the top of the 10-bit address
        -- range instead of overflowing into an 11th bit that gets silently
        -- dropped incorrectly.
        CurrentProgramCounter <= std_logic_vector(to_unsigned(1023, 10));
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 0
            report "SEQUENTIAL WRAPAROUND FAILED" severity failure;

        -- ---- beq, taken (ZeroFlag=1 matches BranchOnZero=1): forward ----
        -- branch, PC=50 + 5 -> 55
        CurrentProgramCounter <= std_logic_vector(to_unsigned(50, 10));
        BranchEnable    <= '1';
        BranchOnZero    <= '1'; -- beq
        ZeroFlag        <= '1'; -- rs = rt
        BranchImmediate <= std_logic_vector(to_unsigned(5, 10));
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 55
            report "BEQ TAKEN (FORWARD) FAILED" severity failure;

        -- ---- beq, taken: backward branch (a loop) -- PC=50 + (-5) -> 45 ----
        BranchImmediate <= std_logic_vector(to_signed(-5, 10));
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 45
            report "BEQ TAKEN (BACKWARD / LOOP) FAILED" severity failure;

        -- ---- beq, NOT taken (ZeroFlag=0 does not match BranchOnZero=1): ----
        -- ---- falls through to sequential (PC=50 -> 51), ignoring the ----
        -- ---- branch immediate entirely ----
        ZeroFlag <= '0'; -- rs /= rt
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 51
            report "BEQ NOT TAKEN FAILED (did not fall through to sequential)" severity failure;

        -- ---- bne, taken (ZeroFlag=0 matches BranchOnZero=0): PC=50+5->55 ----
        BranchOnZero    <= '0'; -- bne
        ZeroFlag        <= '0'; -- rs /= rt
        BranchImmediate <= std_logic_vector(to_unsigned(5, 10));
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 55
            report "BNE TAKEN FAILED" severity failure;

        -- ---- bne, NOT taken (ZeroFlag=1 does not match BranchOnZero=0): ----
        -- ---- falls through to sequential ----
        ZeroFlag <= '1'; -- rs = rt
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 51
            report "BNE NOT TAKEN FAILED (did not fall through to sequential)" severity failure;

        -- ---- jump: overrides everything, including an active branch ----
        -- ---- condition, going straight to the absolute address ----
        BranchEnable <= '1';
        BranchOnZero <= '1';
        ZeroFlag     <= '1'; -- this branch condition IS satisfied...
        JumpEnable   <= '1'; -- ...but jump must still win
        JumpAddress  <= std_logic_vector(to_unsigned(700, 10));
        wait for 10 ns;
        assert unsigned(NextProgramCounter) = 700
            report "JUMP DID NOT TAKE PRIORITY OVER AN ACTIVE BRANCH" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
