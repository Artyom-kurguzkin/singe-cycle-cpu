library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires real ControlUnit, Alu32, and PcUnit
-- together with a clocked PC register standing in for cpu.vhd's future
-- one. Derives BranchEnable/BranchOnZero/ZeroFlag from a real decode and a
-- real ALU comparison rather than driving them directly, proving the
-- three modules cooperate.
--
-- Sequence (hand-crafted loop/exit/jump/ordinary-instruction program):
--   PC=5:   bne, operands unequal -> taken, offset -2 -> PC=3 (loop back)
--   PC=3:   bne, operands equal -> not taken -> PC=4
--   PC=4:   jump to 100 (unconditional, overrides everything) -> PC=100
--   PC=100: add (ordinary R-type, doesn't touch PC) -> PC=101
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

    -- Stands in for cpu.vhd's future PC register.
    signal ProgramCounter : STD_LOGIC_VECTOR (9 downto 0) := std_logic_vector(to_unsigned(5, 10));

    -- Stand-ins for instruction fields a real decoder would extract.
    signal InstructionOpCode       : STD_LOGIC_VECTOR (5 downto 0) := (others => '0');
    signal InstructionFunctionCode : STD_LOGIC_VECTOR (2 downto 0) := (others => '0');
    signal BranchImmediate         : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal JumpAddress             : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');

    -- Stand-ins for two operand registers' values, feeding Alu32 directly
    -- (no RegisterFile needed for this narrow scope).
    signal OperandA : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal OperandB : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

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
        -- ---- PC=5: bne with unequal operands -> taken, offset -2 ----
        assert unsigned(ProgramCounter) = 5
            report "INITIAL PC WAS NOT 5" severity failure;
        InstructionOpCode       <= "000100"; -- bne
        InstructionFunctionCode <= "000";
        OperandA <= std_logic_vector(to_unsigned(3, 32));
        OperandB <= std_logic_vector(to_unsigned(7, 32)); -- unequal -> ZeroFlag=0 -> taken
        BranchImmediate <= std_logic_vector(to_signed(-2, 10));
        wait for 1 ns;
        assert AluZeroFlag = '0'
            report "ALU DID NOT REPORT UNEQUAL OPERANDS AS NON-ZERO" severity failure;
        assert unsigned(NextProgramCounter) = 3
            report "BNE (TAKEN, BACKWARD) DID NOT COMPUTE PC=3" severity failure;
        wait until rising_edge(Clock);

        -- ---- PC=3: bne with equal operands -> not taken, PC=3+1=4 ----
        wait for 1 ns;
        assert unsigned(ProgramCounter) = 3
            report "PC DID NOT ADVANCE TO 3 AFTER THE TAKEN BRANCH" severity failure;
        OperandA <= std_logic_vector(to_unsigned(4, 32));
        OperandB <= std_logic_vector(to_unsigned(4, 32)); -- equal -> ZeroFlag=1 -> not taken
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
