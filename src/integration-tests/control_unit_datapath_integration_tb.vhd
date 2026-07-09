library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires a real ControlUnit with real RegisterFile,
-- Alu32, and DataMemory, driven by hand-picked OpCode/FunctionCode/
-- register-field values standing in for decoded instructions. Covers the
-- full non-branching, non-jumping datapath (no PcUnit or instruction-field
-- extraction yet).
--
-- The key case is `load immediate`: it seeds the instruction's (ISA-unused)
-- rs field with nonzero garbage, then confirms the write-back result is
-- still exactly the immediate -- proving AluOperandAZero actually forces
-- the ALU's first operand to zero rather than leaking rs's value through.
entity ControlUnitDatapathIntegrationTb is
end ControlUnitDatapathIntegrationTb;

architecture Behavioral of ControlUnitDatapathIntegrationTb is

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

    component RegisterFile is
        Port (
            Clock                : in  STD_LOGIC;
            ReadRegisterAddress1 : in  STD_LOGIC_VECTOR (3 downto 0);
            ReadRegisterAddress2 : in  STD_LOGIC_VECTOR (3 downto 0);
            ReadData1            : out STD_LOGIC_VECTOR (31 downto 0);
            ReadData2            : out STD_LOGIC_VECTOR (31 downto 0);
            WriteRegisterAddress : in  STD_LOGIC_VECTOR (3 downto 0);
            WriteData            : in  STD_LOGIC_VECTOR (31 downto 0);
            RegisterWriteEnable  : in  STD_LOGIC
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

    component DataMemory is
        Port (
            Clock             : in  STD_LOGIC;
            Address           : in  STD_LOGIC_VECTOR (7 downto 0);
            WriteData         : in  STD_LOGIC_VECTOR (31 downto 0);
            MemoryWriteEnable : in  STD_LOGIC;
            ReadData          : out STD_LOGIC_VECTOR (31 downto 0);
            IoAddress         : out STD_LOGIC_VECTOR (7 downto 0);
            IoData            : out STD_LOGIC_VECTOR (31 downto 0);
            IoEnable          : out STD_LOGIC
        );
    end component;

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    -- Stand-ins for fields a real instruction decoder would extract.
    signal RsField        : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RtField        : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RdField        : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ImmediateValue : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal InstructionOpCode       : STD_LOGIC_VECTOR (5 downto 0) := (others => '0');
    signal InstructionFunctionCode : STD_LOGIC_VECTOR (2 downto 0) := (others => '0');

    signal RegisterDestinationSelect : STD_LOGIC;
    signal AluSourceSelect           : STD_LOGIC;
    signal AluOperandAZero           : STD_LOGIC;
    signal MemoryToRegisterSelect    : STD_LOGIC;
    signal ControlRegisterWriteEnable : STD_LOGIC;
    signal ControlMemoryWriteEnable   : STD_LOGIC;
    signal BranchEnable : STD_LOGIC;
    signal BranchOnZero : STD_LOGIC;
    signal JumpEnable   : STD_LOGIC;
    signal DecodedAluOpCode : STD_LOGIC_VECTOR (2 downto 0);

    signal RegisterReadData1    : STD_LOGIC_VECTOR (31 downto 0);
    signal RegisterReadData2    : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0);
    signal RegisterWriteDataMux : STD_LOGIC_VECTOR (31 downto 0);

    -- Raw register-file write signals used only to seed initial values,
    -- bypassing ControlUnit (a seed isn't a real decoded instruction).
    signal SeedWriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal SeedWriteData            : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal SeedWriteEnable          : STD_LOGIC := '0';

    -- '1' during seed writes, '0' for decoded-instruction steps -- both
    -- share the one register-file write port.
    signal UseSeedWrite : STD_LOGIC := '1';

    signal AluOperandA : STD_LOGIC_VECTOR (31 downto 0);
    signal AluOperandB : STD_LOGIC_VECTOR (31 downto 0);
    signal AluResult   : STD_LOGIC_VECTOR (31 downto 0);

    signal MemoryAddress  : STD_LOGIC_VECTOR (7 downto 0);
    signal MemoryReadData : STD_LOGIC_VECTOR (31 downto 0);

begin

    ControlUnitUnderTest: ControlUnit
        port map (
            OpCode                    => InstructionOpCode,
            FunctionCode              => InstructionFunctionCode,
            RegisterDestinationSelect => RegisterDestinationSelect,
            AluSourceSelect           => AluSourceSelect,
            ImmediateZeroExtend       => open, -- ImmediateValue is driven pre-extended
            AluOperandAZero           => AluOperandAZero,
            MemoryToRegisterSelect    => MemoryToRegisterSelect,
            RegisterWriteEnable       => ControlRegisterWriteEnable,
            MemoryWriteEnable         => ControlMemoryWriteEnable,
            BranchEnable              => BranchEnable,
            BranchOnZero              => BranchOnZero,
            JumpEnable                => JumpEnable,
            AluOpCode                 => DecodedAluOpCode
        );

    -- RegDst mux, with a seed-write override.
    WriteRegisterAddress <= SeedWriteRegisterAddress when UseSeedWrite = '1' else
                            RdField when RegisterDestinationSelect = '1' else RtField;

    -- MemToReg mux, with a seed-write override.
    RegisterWriteDataMux <= SeedWriteData when UseSeedWrite = '1' else
                            MemoryReadData when MemoryToRegisterSelect = '1' else AluResult;

    RegisterFileUnderTest: RegisterFile
        port map (
            Clock                => Clock,
            ReadRegisterAddress1 => RsField,
            ReadRegisterAddress2 => RtField,
            ReadData1            => RegisterReadData1,
            ReadData2            => RegisterReadData2,
            WriteRegisterAddress => WriteRegisterAddress,
            WriteData            => RegisterWriteDataMux,
            RegisterWriteEnable  => (SeedWriteEnable or (ControlRegisterWriteEnable and not UseSeedWrite))
        );

    AluOperandA <= (others => '0') when AluOperandAZero = '1' else RegisterReadData1;
    AluOperandB <= ImmediateValue when AluSourceSelect = '1' else RegisterReadData2;

    Alu32UnderTest: Alu32
        port map (
            OperandA => AluOperandA,
            OperandB => AluOperandB,
            OpCode   => DecodedAluOpCode,
            Result   => AluResult,
            ZeroFlag => open
        );

    MemoryAddress <= AluResult(7 downto 0);

    DataMemoryUnderTest: DataMemory
        port map (
            Clock             => Clock,
            Address           => MemoryAddress,
            WriteData         => RegisterReadData2, -- rt: the value store writes
            MemoryWriteEnable => ControlMemoryWriteEnable,
            ReadData          => MemoryReadData,
            IoAddress         => open,
            IoData            => open,
            IoEnable          => open
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

    Stimulus: process
    begin
        -- ---- Seed r1=5, r2=7 (for the R-type add case) ----
        UseSeedWrite <= '1';
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(1, 4));
        SeedWriteData            <= std_logic_vector(to_unsigned(5, 32));
        SeedWriteEnable          <= '1';
        wait until rising_edge(Clock);
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(2, 4));
        SeedWriteData            <= std_logic_vector(to_unsigned(7, 32));
        wait until rising_edge(Clock);

        -- ---- Seed r5 with nonzero garbage (load-immediate's rs points ----
        -- ---- here and must ignore it) ----
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(5, 4));
        SeedWriteData            <= x"BADBADBA";
        wait until rising_edge(Clock);

        -- ---- Seed r7=20 (base address), r8=0xCAFE (store data) ----
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(7, 4));
        SeedWriteData            <= std_logic_vector(to_unsigned(20, 32));
        wait until rising_edge(Clock);
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(8, 4));
        SeedWriteData            <= x"0000CAFE";
        wait until rising_edge(Clock);
        SeedWriteEnable <= '0';
        UseSeedWrite    <= '0';

        -- ---- add r3, r1, r2 ----
        InstructionOpCode       <= "000000";
        InstructionFunctionCode <= "000"; -- add
        RsField <= std_logic_vector(to_unsigned(1, 4));
        RtField <= std_logic_vector(to_unsigned(2, 4));
        RdField <= std_logic_vector(to_unsigned(3, 4));
        wait for 1 ns;
        assert unsigned(AluResult) = 12
            report "CONTROL-DRIVEN ADD PRODUCED WRONG ALU RESULT" severity failure;
        wait until rising_edge(Clock);

        RsField <= std_logic_vector(to_unsigned(3, 4)); -- read back r3
        wait for 1 ns;
        assert unsigned(RegisterReadData1) = 12
            report "CONTROL-DRIVEN ADD WRITE-BACK FAILED" severity failure;

        -- ---- load immediate r6, 0x1234, with rs=r5 (garbage-seeded) ----
        InstructionOpCode       <= "100010";
        InstructionFunctionCode <= "000";
        RsField <= std_logic_vector(to_unsigned(5, 4)); -- garbage; must be ignored
        RtField <= std_logic_vector(to_unsigned(6, 4));
        ImmediateValue <= x"00001234";
        wait for 1 ns;
        assert AluResult = x"00001234"
            report "LOAD IMMEDIATE WAS CORRUPTED BY GARBAGE IN THE UNUSED rs FIELD -- AluOperandAZero is not working" severity failure;
        wait until rising_edge(Clock);

        RsField <= std_logic_vector(to_unsigned(6, 4)); -- read back r6
        wait for 1 ns;
        assert RegisterReadData1 = x"00001234"
            report "CONTROL-DRIVEN LOAD IMMEDIATE WRITE-BACK FAILED" severity failure;

        -- ---- store r8, r7, 5 -> address = r7 + 5 = 25, data = r8 ----
        InstructionOpCode       <= "100001";
        InstructionFunctionCode <= "000";
        RsField <= std_logic_vector(to_unsigned(7, 4));
        RtField <= std_logic_vector(to_unsigned(8, 4));
        ImmediateValue <= std_logic_vector(to_unsigned(5, 32));
        wait for 1 ns;
        assert unsigned(AluResult) = 25
            report "CONTROL-DRIVEN STORE ADDRESS CALC FAILED" severity failure;
        wait until rising_edge(Clock);

        -- ---- load r9, r7, 5 -> reads back the word just stored ----
        InstructionOpCode       <= "100011";
        InstructionFunctionCode <= "000";
        RsField <= std_logic_vector(to_unsigned(7, 4));
        RtField <= std_logic_vector(to_unsigned(9, 4));
        ImmediateValue <= std_logic_vector(to_unsigned(5, 32));
        wait for 1 ns;
        assert MemoryReadData = x"0000CAFE"
            report "CONTROL-DRIVEN LOAD DID NOT READ BACK THE STORED VALUE" severity failure;
        wait until rising_edge(Clock);

        RsField <= std_logic_vector(to_unsigned(9, 4)); -- read back r9
        wait for 1 ns;
        assert RegisterReadData1 = x"0000CAFE"
            report "CONTROL-DRIVEN LOAD WRITE-BACK FAILED" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
