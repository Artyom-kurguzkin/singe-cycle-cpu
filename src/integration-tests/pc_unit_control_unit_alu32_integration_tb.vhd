library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires real ControlUnit, Alu32, and PcUnit
-- instances together with a clocked PC register standing in for the one
-- cpu.vhd will eventually own (the same "stand-in register, real logic"
-- approach used by alu32_instruction_memory_integration_tb.vhd for the
-- fetch-address preview in Step 4). Unlike pc_unit_tb.vhd, which drives
-- BranchEnable/BranchOnZero/ZeroFlag directly, this test derives all three
-- from a real ControlUnit decode and a real Alu32 comparison -- proving the
-- three modules cooperate correctly, not just that each one works in
-- isolation.
--
-- Modelled sequence (a tiny hand-crafted "loop, exit, jump, ordinary
-- instruction" program -- deliberately not using InstructionMemory's
-- placeholder words, since those are arbitrary bit patterns that don't
-- decode to anything meaningful; a real fetch-from-memory version of this
-- is cpu_tb.vhd's job once cpu.vhd exists in Step 8):
--   PC=5:   bne r?,r?  (operands unequal -> ZeroFlag=0 -> bne condition met)
--           branch taken, offset -2 -> PC becomes 3 (a backward loop)
--   PC=3:   bne r?,r?  (operands EQUAL -> ZeroFlag=1 -> bne condition NOT met)
--           falls through -> PC becomes 4
--   PC=4:   jump to address 100 (unconditional, overrides everything)
--           PC becomes 100
--   PC=100: add (ordinary R-type, doesn't touch PC) -> PC becomes 101
entity PcUnitControlUnitAlu32IntegrationTb is
end PcUnitControlUnitAlu32IntegrationTb;

architecture Behavioral of PcUnitControlUnitAlu32IntegrationTb is

    component ControlUnit is
        Port (
            OpCode                    : in  STD_LOGIC_VECTOR (5 downto 0);
            FunctionCode              : in  STD_LOGIC_VECTOR (2 downto 0);
            RegisterDestinationSelect : out STD_LOGIC;
            AluSourceSelect           : out STD_LOGIC;
            ImmediateZeroExtend       : out STD_LOGIC;
            AluOperandAZero           : out STD_LOGIC;
            MemoryToRegisterSelect    : out STD_LOGIC;
            RegisterWriteEnable       : out STD_LOGIC;
            MemoryWriteEnable         : out STD_LOGIC;
            BranchEnable              : out STD_LOGIC;
            BranchOnZero              : out STD_LOGIC;
            JumpEnable                : out STD_LOGIC;
            AluOpCode                 : out STD_LOGIC_VECTOR (2 downto 0)
        );
    end component;

    component Alu32 is
        Port (
            OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
            OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
            OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
            Result   : out STD_LOGIC_VECTOR (31 downto 0);
            ZeroFlag : out STD_LOGIC
        );
    end component;

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

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    -- Stands in for cpu.vhd's future PC register -- PcUnit itself has no
    -- register (see pc_unit.vhd's header comment), so this testbench
    -- provides the clocked storage the real top level will eventually own.
    signal ProgramCounter : STD_LOGIC_VECTOR (9 downto 0) := std_logic_vector(to_unsigned(5, 10));

    -- Stand-ins for instruction fields a real decoder would extract from a
    -- fetched instruction word (same approach as every earlier integration
    -- test in this project).
    signal InstructionOpCode       : STD_LOGIC_VECTOR (5 downto 0) := (others => '0');
    signal InstructionFunctionCode : STD_LOGIC_VECTOR (2 downto 0) := (others => '0');
    signal BranchImmediate         : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal JumpAddress             : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');

    -- Stand-ins for two operand registers' values, feeding Alu32 directly
    -- (no RegisterFile needed for this narrow scope -- this test is about
    -- PcUnit/ControlUnit/Alu32 cooperating, not the full datapath, which is
    -- what control_unit_datapath_integration_tb.vhd from Step 6 already
    -- covers for the non-branching instructions).
    signal OperandA : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal OperandB : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

    -- ControlUnit outputs (only the ones this test actually needs are
    -- given descriptive local names; the rest are still wired through so
    -- the component instantiation is complete).
    signal BranchEnable : STD_LOGIC;
    signal BranchOnZero : STD_LOGIC;
    signal JumpEnable   : STD_LOGIC;
    signal DecodedAluOpCode : STD_LOGIC_VECTOR (2 downto 0);

    signal AluZeroFlag : STD_LOGIC;
    signal NextProgramCounter : STD_LOGIC_VECTOR (9 downto 0);

begin

    ControlUnitUnderTest: ControlUnit
        port map (
            OpCode                    => InstructionOpCode,
            FunctionCode              => InstructionFunctionCode,
            RegisterDestinationSelect => open,
            AluSourceSelect           => open,
            ImmediateZeroExtend       => open,
            AluOperandAZero           => open,
            MemoryToRegisterSelect    => open,
            RegisterWriteEnable       => open,
            MemoryWriteEnable         => open,
            BranchEnable              => BranchEnable,
            BranchOnZero              => BranchOnZero,
            JumpEnable                => JumpEnable,
            AluOpCode                 => DecodedAluOpCode
        );

    Alu32UnderTest: Alu32
        port map (
            OperandA => OperandA,
            OperandB => OperandB,
            OpCode   => DecodedAluOpCode,
            Result   => open,
            ZeroFlag => AluZeroFlag
        );

    PcUnitUnderTest: PcUnit
        port map (
            CurrentProgramCounter => ProgramCounter,
            BranchEnable          => BranchEnable,
            BranchOnZero          => BranchOnZero,
            ZeroFlag              => AluZeroFlag,
            JumpEnable            => JumpEnable,
            BranchImmediate       => BranchImmediate,
            JumpAddress           => JumpAddress,
            NextProgramCounter    => NextProgramCounter
        );

    -- A free-running clock, needed to advance ProgramCounter the same way
    -- a real PC register advances once per instruction.
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

    -- Stands in for cpu.vhd's future PC register update.
    ProgramCounterUpdate: process (Clock)
    begin
        if rising_edge(Clock) then
            ProgramCounter <= NextProgramCounter;
        end if;
    end process;

    Stimulus: process
    begin
        -- ---- PC=5: bne with unequal operands -> branch taken, offset -2 ----
        assert unsigned(ProgramCounter) = 5
            report "INITIAL PC WAS NOT 5" severity failure;
        InstructionOpCode       <= "000100"; -- bne
        InstructionFunctionCode <= "000";
        OperandA <= std_logic_vector(to_unsigned(3, 32));
        OperandB <= std_logic_vector(to_unsigned(7, 32)); -- unequal -> ZeroFlag=0 -> bne taken
        BranchImmediate <= std_logic_vector(to_signed(-2, 10));
        wait for 1 ns; -- let the combinational decode/ALU/PcUnit chain settle
        assert AluZeroFlag = '0'
            report "ALU DID NOT REPORT UNEQUAL OPERANDS AS NON-ZERO" severity failure;
        assert unsigned(NextProgramCounter) = 3
            report "BNE (TAKEN, BACKWARD) DID NOT COMPUTE PC=3" severity failure;
        wait until rising_edge(Clock);

        -- ---- PC=3: bne with equal operands -> branch NOT taken, PC=3+1=4 ----
        wait for 1 ns;
        assert unsigned(ProgramCounter) = 3
            report "PC DID NOT ADVANCE TO 3 AFTER THE TAKEN BRANCH" severity failure;
        OperandA <= std_logic_vector(to_unsigned(4, 32));
        OperandB <= std_logic_vector(to_unsigned(4, 32)); -- equal -> ZeroFlag=1 -> bne NOT taken
        wait for 1 ns;
        assert AluZeroFlag = '1'
            report "ALU DID NOT REPORT EQUAL OPERANDS AS ZERO" severity failure;
        assert unsigned(NextProgramCounter) = 4
            report "BNE (NOT TAKEN) DID NOT FALL THROUGH TO PC=4" severity failure;
        wait until rising_edge(Clock);

        -- ---- PC=4: jump to 100, unconditionally ----
        wait for 1 ns;
        assert unsigned(ProgramCounter) = 4
            report "PC DID NOT ADVANCE TO 4 AFTER THE NOT-TAKEN BRANCH" severity failure;
        InstructionOpCode <= "000010"; -- jump
        JumpAddress       <= std_logic_vector(to_unsigned(100, 10));
        wait for 1 ns;
        assert unsigned(NextProgramCounter) = 100
            report "JUMP DID NOT COMPUTE PC=100" severity failure;
        wait until rising_edge(Clock);

        -- ---- PC=100: an ordinary R-type add, PC just advances to 101 ----
        wait for 1 ns;
        assert unsigned(ProgramCounter) = 100
            report "PC DID NOT ADVANCE TO 100 AFTER THE JUMP" severity failure;
        InstructionOpCode       <= "000000"; -- add
        InstructionFunctionCode <= "000";
        wait for 1 ns;
        assert unsigned(NextProgramCounter) = 101
            report "ORDINARY INSTRUCTION DID NOT ADVANCE PC SEQUENTIALLY" severity failure;
        wait until rising_edge(Clock);

        wait for 1 ns;
        assert unsigned(ProgramCounter) = 101
            report "PC DID NOT ADVANCE TO 101" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
