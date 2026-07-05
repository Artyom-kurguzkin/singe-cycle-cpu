library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires a real ControlUnit together with real
-- RegisterFile, Alu32, and DataMemory instances (no mocking of any of
-- them) and drives it with hand-picked OpCode/FunctionCode/register-field
-- values standing in for actual decoded instructions -- this is the full
-- non-branching, non-jumping single-cycle datapath, missing only PcUnit
-- (Step 7) and the instruction-field extraction cpu.vhd will eventually do
-- (RsField/RtField/RdField/ImmediateValue are driven directly here, the
-- same stand-in approach used by every earlier integration test in this
-- project).
--
-- The most important case below is `load immediate`: it specifically
-- proves the AluOperandAZero signal this project's control_unit.vhd added
-- beyond the plan's original sketch (see that file's header comment) is
-- actually necessary -- by first seeding the instruction's (unused, per
-- the ISA) rs field with a nonzero garbage value, then confirming the
-- write-back result is still exactly the immediate, unaffected by that
-- garbage. Without AluOperandAZero forcing the ALU's first operand to
-- zero, this case would silently compute "garbage + immediate" instead.
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

    -- Stand-ins for instruction fields a real instruction decoder (inside
    -- cpu.vhd, eventually) would extract from the 32-bit instruction word.
    signal RsField        : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RtField        : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RdField        : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ImmediateValue : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal InstructionOpCode       : STD_LOGIC_VECTOR (5 downto 0) := (others => '0');
    signal InstructionFunctionCode : STD_LOGIC_VECTOR (2 downto 0) := (others => '0');

    -- ControlUnit outputs.
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

    -- RegisterFile signals.
    signal RegisterReadData1    : STD_LOGIC_VECTOR (31 downto 0);
    signal RegisterReadData2    : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0);
    signal RegisterWriteDataMux : STD_LOGIC_VECTOR (31 downto 0);

    -- Raw (bypassing ControlUnit) register-file write signals, used only to
    -- seed initial register values -- the same "seed" approach used by
    -- every earlier integration test in this project, since a seed isn't a
    -- real instruction being decoded.
    signal SeedWriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal SeedWriteData            : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal SeedWriteEnable          : STD_LOGIC := '0';

    -- Selects between a real decoded instruction's write (via ControlUnit)
    -- and a raw seed write, since both share the one register file write
    -- port. Held '1' during the seed steps at the start of the stimulus
    -- process, '0' for every decoded-instruction step afterwards.
    signal UseSeedWrite : STD_LOGIC := '1';

    -- Alu32 signals.
    signal AluOperandA : STD_LOGIC_VECTOR (31 downto 0);
    signal AluOperandB : STD_LOGIC_VECTOR (31 downto 0);
    signal AluResult   : STD_LOGIC_VECTOR (31 downto 0);

    -- DataMemory signals.
    signal MemoryAddress  : STD_LOGIC_VECTOR (7 downto 0);
    signal MemoryReadData : STD_LOGIC_VECTOR (31 downto 0);

begin

    ControlUnitUnderTest: ControlUnit
        port map (
            OpCode                    => InstructionOpCode,
            FunctionCode              => InstructionFunctionCode,
            RegisterDestinationSelect => RegisterDestinationSelect,
            AluSourceSelect           => AluSourceSelect,
            ImmediateZeroExtend       => open, -- this test drives ImmediateValue pre-extended already
            AluOperandAZero           => AluOperandAZero,
            MemoryToRegisterSelect    => MemoryToRegisterSelect,
            RegisterWriteEnable       => ControlRegisterWriteEnable,
            MemoryWriteEnable         => ControlMemoryWriteEnable,
            BranchEnable              => BranchEnable,
            BranchOnZero              => BranchOnZero,
            JumpEnable                => JumpEnable,
            AluOpCode                 => DecodedAluOpCode
        );

    -- RegDst mux: picks rd (R-type) or rt (I-type writers) as the write
    -- destination, unless a raw seed write is in progress.
    WriteRegisterAddress <= SeedWriteRegisterAddress when UseSeedWrite = '1' else
                            RdField when RegisterDestinationSelect = '1' else RtField;

    -- MemToReg mux: picks DataMemory's read data or the ALU's result as the
    -- value actually written back, unless a raw seed write is in progress.
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

    -- AluOperandAZero mux: forces zero for load-immediate; otherwise rs.
    AluOperandA <= (others => '0') when AluOperandAZero = '1' else RegisterReadData1;

    -- ALUSrc mux: immediate for load-immediate/load/store; otherwise rt.
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

    -- A free-running clock, needed because both RegisterFile's and
    -- DataMemory's write ports are synchronous.
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
        -- ---- Seed r1 = 5, r2 = 7 (for the R-type add case below) ----
        UseSeedWrite <= '1';
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(1, 4));
        SeedWriteData            <= std_logic_vector(to_unsigned(5, 32));
        SeedWriteEnable          <= '1';
        wait until rising_edge(Clock);
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(2, 4));
        SeedWriteData            <= std_logic_vector(to_unsigned(7, 32));
        wait until rising_edge(Clock);

        -- ---- Seed r5 with nonzero garbage (the load-immediate case's ----
        -- ---- rs field will point here, and must be ignored) ----
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(5, 4));
        SeedWriteData            <= x"BADBADBA";
        wait until rising_edge(Clock);

        -- ---- Seed r7 = 20 (base address), r8 = 0xCAFE (store data) ----
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(7, 4));
        SeedWriteData            <= std_logic_vector(to_unsigned(20, 32));
        wait until rising_edge(Clock);
        SeedWriteRegisterAddress <= std_logic_vector(to_unsigned(8, 4));
        SeedWriteData            <= x"0000CAFE";
        wait until rising_edge(Clock);
        SeedWriteEnable <= '0';
        UseSeedWrite    <= '0';

        -- ---- Decoded instruction 1: add r3, r1, r2 (mimics "add r1 r2 r3": ----
        -- ---- rs=r1, rt=r2, rd=r3, per this ISA's rs/rt/rd field order) ----
        InstructionOpCode       <= "000000";
        InstructionFunctionCode <= "000"; -- add
        RsField <= std_logic_vector(to_unsigned(1, 4));
        RtField <= std_logic_vector(to_unsigned(2, 4));
        RdField <= std_logic_vector(to_unsigned(3, 4));
        wait for 1 ns; -- let the whole combinational chain settle
        assert unsigned(AluResult) = 12
            report "CONTROL-DRIVEN ADD PRODUCED WRONG ALU RESULT" severity failure;
        wait until rising_edge(Clock);

        RsField <= std_logic_vector(to_unsigned(3, 4)); -- read back r3
        wait for 1 ns;
        assert unsigned(RegisterReadData1) = 12
            report "CONTROL-DRIVEN ADD WRITE-BACK FAILED" severity failure;

        -- ---- Decoded instruction 2: load immediate r6, 0x1234, with ----
        -- ---- rs=r5 (the garbage-seeded register) in the unused rs field ----
        InstructionOpCode       <= "100010";
        InstructionFunctionCode <= "000"; -- don't-care for I-type
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

        -- ---- Decoded instruction 3: store r8, r7, 5 (mimics "store r8 r7 5": ----
        -- ---- address = r7 + 5 = 25, data = r8 = 0xCAFE) ----
        InstructionOpCode       <= "100001";
        InstructionFunctionCode <= "000";
        RsField <= std_logic_vector(to_unsigned(7, 4));
        RtField <= std_logic_vector(to_unsigned(8, 4));
        ImmediateValue <= std_logic_vector(to_unsigned(5, 32));
        wait for 1 ns;
        assert unsigned(AluResult) = 25
            report "CONTROL-DRIVEN STORE ADDRESS CALC FAILED" severity failure;
        wait until rising_edge(Clock);

        -- ---- Decoded instruction 4: load r9, r7, 5 (mimics "load r9 r7 5": ----
        -- ---- reads back the exact word instruction 3 just stored) ----
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
