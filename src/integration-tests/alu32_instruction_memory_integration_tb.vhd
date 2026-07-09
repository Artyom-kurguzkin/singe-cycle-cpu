library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ProgramLoaderPkg.ALL;

-- Integration testbench: previews the fetch-next-instruction interaction
-- between a PC and InstructionMemory, using a real Alu32 (computing PC + 1
-- via `inc`) and a real InstructionMemory (fetching at the resulting
-- address). No PC unit exists yet, so a plain signal here plays that role,
-- advanced each clock edge.
--
-- Sequence: starting at address 0, repeatedly compute CurrentAddress + 1
-- through the real ALU and fetch through the real instruction memory,
-- checking addresses 0, 1, 2 come back in order with the expected words.
entity Alu32InstructionMemoryIntegrationTb is
end Alu32InstructionMemoryIntegrationTb;

architecture Behavioral of Alu32InstructionMemoryIntegrationTb is

    component Alu32 is
        Port (
            OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
            OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
            OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
            Result   : out STD_LOGIC_VECTOR (31 downto 0);
            ZeroFlag : out STD_LOGIC
        );
    end component;

    component InstructionMemory is
        Generic (
            ProgramData : STD_LOGIC_VECTOR (32767 downto 0)
        );
        Port (
            Address        : in  STD_LOGIC_VECTOR (9 downto 0);
            InstructionOut : out STD_LOGIC_VECTOR (31 downto 0)
        );
    end component;

    constant TestProgram : STD_LOGIC_VECTOR (32767 downto 0) :=
        LoadProgramFromFile("tools/programs/cpu_test_program.bin");

    signal Clock          : STD_LOGIC := '0';
    signal StopClock      : BOOLEAN := false;

    -- Stands in for the not-yet-built PC register.
    signal CurrentAddress : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');

    -- OperandA is CurrentAddress zero-extended to 32 bits; OperandB is
    -- unused by inc, tied to zero.
    signal AluOperandA    : STD_LOGIC_VECTOR (31 downto 0);
    signal AluResult      : STD_LOGIC_VECTOR (31 downto 0);

    signal FetchedInstruction : STD_LOGIC_VECTOR (31 downto 0);

begin

    AluOperandA <= STD_LOGIC_VECTOR(resize(unsigned(CurrentAddress), 32));

    Alu32UnderTest: Alu32
        port map (
            OperandA => AluOperandA,
            OperandB => (others => '0'),
            OpCode   => "111", -- inc: CurrentAddress + 1
            Result   => AluResult,
            ZeroFlag => open
        );

    InstructionMemoryUnderTest: InstructionMemory
        generic map (
            ProgramData => TestProgram
        )
        port map (
            Address        => CurrentAddress,
            InstructionOut => FetchedInstruction
        );

    ClockGeneration: process
    begin
        while not StopClock loop
            Clock <= '0';
            wait for 10 ns;
            Clock <= '1';
            wait for 10 ns;
        end loop;
        wait;
    end process;

    -- Advances CurrentAddress to the ALU's "+1" result each rising edge,
    -- standing in for a real PC register's clocked update.
    AddressAdvance: process (Clock)
    begin
        if rising_edge(Clock) then
            CurrentAddress <= AluResult(9 downto 0);
        end if;
    end process;

    Stimulus: process
    begin
        -- ---- Address 0 (starting address, before any clock edge) ----
        wait for 1 ns;
        assert FetchedInstruction = x"88000000" -- load immediate r0, 0
            report "FETCH AT ADDRESS 0 FAILED" severity failure;

        -- ---- Address 1, via one ALU-computed increment ----
        wait until rising_edge(Clock);
        wait for 1 ns;
        assert unsigned(CurrentAddress) = 1
            report "ALU DID NOT ADVANCE ADDRESS TO 1" severity failure;
        assert FetchedInstruction = x"88040028" -- load immediate r1, 10
            report "FETCH AT ADDRESS 1 FAILED" severity failure;

        -- ---- Address 2, via a second ALU-computed increment ----
        wait until rising_edge(Clock);
        wait for 1 ns;
        assert unsigned(CurrentAddress) = 2
            report "ALU DID NOT ADVANCE ADDRESS TO 2" severity failure;
        assert FetchedInstruction = x"88080050" -- load immediate r2, 20
            report "FETCH AT ADDRESS 2 FAILED" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
