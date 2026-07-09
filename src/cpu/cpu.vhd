library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Top-level single-cycle CPU: structurally wires InstructionMemory,
-- ControlUnit, RegisterFile, Alu32, DataMemory, and PcUnit together, plus
-- the PC register and instruction-field extraction that don't belong to
-- any one module.
entity Cpu is
    Generic (
        -- Forwarded to InstructionMemory's own ProgramData generic. Cpu
        -- never reads a file itself; whatever instantiates it supplies
        -- the compiled program.
        ProgramData : STD_LOGIC_VECTOR (32767 downto 0)
    );
    Port (
        -- No reset pin: PC/RegisterFile/DataMemory all get their t=0 value
        -- from signal initializers.
        clk       : in  STD_LOGIC;

        -- Pass-through of DataMemory's IoAddress/IoData/IoEnable. Valid
        -- for one cycle per `store` that targets the IO half (128-255) of
        -- the address space.
        ioaddress : out STD_LOGIC_VECTOR (7 downto 0);
        iodata    : out STD_LOGIC_VECTOR (31 downto 0);
        ioenable  : out STD_LOGIC
    );
end Cpu;

architecture Structural of Cpu is

    component InstructionMemory is
        Generic (
            ProgramData : STD_LOGIC_VECTOR (32767 downto 0)
        );
        Port (
            Address        : in  STD_LOGIC_VECTOR (9 downto 0);
            InstructionOut : out STD_LOGIC_VECTOR (31 downto 0)
        );
    end component;

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

    -- PC state: PcUnit only computes the next value, this register holds it.
    signal ProgramCounter     : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal NextProgramCounter : STD_LOGIC_VECTOR (9 downto 0);

    -- Fetched instruction and its extracted fields. OpCode/rs/rt sit at
    -- the same bit positions in every format, so decode can start on
    -- OpCode before knowing the instruction's format.
    signal FetchedInstruction : STD_LOGIC_VECTOR (31 downto 0);
    signal InstructionOpCode  : STD_LOGIC_VECTOR (5 downto 0);
    signal RsField            : STD_LOGIC_VECTOR (3 downto 0);
    signal RtField             : STD_LOGIC_VECTOR (3 downto 0);
    signal RdField            : STD_LOGIC_VECTOR (3 downto 0); -- R-format only
    signal FunctionCode       : STD_LOGIC_VECTOR (2 downto 0); -- R-format only
    signal RawImmediate       : STD_LOGIC_VECTOR (15 downto 0); -- I-format only
    signal JumpAddressField   : STD_LOGIC_VECTOR (9 downto 0); -- J-format only

    -- ControlUnit's decode of the current instruction.
    signal RegisterDestinationSelect : STD_LOGIC;
    signal AluSourceSelect           : STD_LOGIC;
    signal ImmediateZeroExtend       : STD_LOGIC;
    signal AluOperandAZero           : STD_LOGIC;
    signal MemoryToRegisterSelect    : STD_LOGIC;
    signal ControlRegisterWriteEnable : STD_LOGIC;
    signal ControlMemoryWriteEnable   : STD_LOGIC;
    signal BranchEnable : STD_LOGIC;
    signal BranchOnZero : STD_LOGIC;
    signal JumpEnable   : STD_LOGIC;
    signal DecodedAluOpCode : STD_LOGIC_VECTOR (2 downto 0);

    -- RegisterFile's read outputs and write-side muxes.
    signal RegisterReadData1    : STD_LOGIC_VECTOR (31 downto 0);
    signal RegisterReadData2    : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0);
    signal RegisterWriteDataMux : STD_LOGIC_VECTOR (31 downto 0);

    -- Immediate field, extended both ways; ImmediateZeroExtend picks.
    signal SignExtendedImmediate : STD_LOGIC_VECTOR (31 downto 0);
    signal ZeroExtendedImmediate : STD_LOGIC_VECTOR (31 downto 0);
    signal AluImmediateOperand   : STD_LOGIC_VECTOR (31 downto 0);

    -- Alu32's actual operands (post-mux) and outputs.
    signal AluOperandA : STD_LOGIC_VECTOR (31 downto 0);
    signal AluOperandB : STD_LOGIC_VECTOR (31 downto 0);
    signal AluResult   : STD_LOGIC_VECTOR (31 downto 0);
    signal AluZeroFlag : STD_LOGIC;

    -- DataMemory's address (ALU result truncated to 8 bits) and read data.
    signal MemoryAddress  : STD_LOGIC_VECTOR (7 downto 0);
    signal MemoryReadData : STD_LOGIC_VECTOR (31 downto 0);

begin

    ------------------------------------------------------------------
    -- Fetch
    ------------------------------------------------------------------
    InstructionMemoryInstance: InstructionMemory
        generic map (
            ProgramData => ProgramData
        )
        port map (
            Address        => ProgramCounter,
            InstructionOut => FetchedInstruction
        );

    ------------------------------------------------------------------
    -- Decode: split the fetched word into fields. Fields unused by the
    -- current instruction's format are extracted anyway (harmless; no
    -- downstream mux selects them) and fed to ControlUnit.
    ------------------------------------------------------------------
    InstructionOpCode <= FetchedInstruction(31 downto 26);
    RsField           <= FetchedInstruction(25 downto 22);
    RtField           <= FetchedInstruction(21 downto 18);
    RdField           <= FetchedInstruction(17 downto 14);
    FunctionCode      <= FetchedInstruction(13 downto 11);
    RawImmediate      <= FetchedInstruction(17 downto 2);
    JumpAddressField  <= FetchedInstruction(25 downto 16);

    ControlUnitInstance: ControlUnit
        port map (
            OpCode                    => InstructionOpCode,
            FunctionCode              => FunctionCode,
            RegisterDestinationSelect => RegisterDestinationSelect,
            AluSourceSelect           => AluSourceSelect,
            ImmediateZeroExtend       => ImmediateZeroExtend,
            AluOperandAZero           => AluOperandAZero,
            MemoryToRegisterSelect    => MemoryToRegisterSelect,
            RegisterWriteEnable       => ControlRegisterWriteEnable,
            MemoryWriteEnable         => ControlMemoryWriteEnable,
            BranchEnable              => BranchEnable,
            BranchOnZero              => BranchOnZero,
            JumpEnable                => JumpEnable,
            AluOpCode                 => DecodedAluOpCode
        );

    ------------------------------------------------------------------
    -- Register read/write. Write side is set up here but only commits on
    -- the next rising edge, gated by ControlRegisterWriteEnable.
    ------------------------------------------------------------------
    WriteRegisterAddress <= RdField when RegisterDestinationSelect = '1' else RtField;
    RegisterWriteDataMux <= MemoryReadData when MemoryToRegisterSelect = '1' else AluResult;

    RegisterFileInstance: RegisterFile
        port map (
            Clock                => clk,
            ReadRegisterAddress1 => RsField,
            ReadRegisterAddress2 => RtField,
            ReadData1            => RegisterReadData1,
            ReadData2            => RegisterReadData2,
            WriteRegisterAddress => WriteRegisterAddress,
            WriteData            => RegisterWriteDataMux,
            RegisterWriteEnable  => ControlRegisterWriteEnable
        );

    ------------------------------------------------------------------
    -- Execute: extend the immediate, mux the ALU's operands, run the ALU.
    ------------------------------------------------------------------
    SignExtendedImmediate <= std_logic_vector(resize(signed(RawImmediate), 32));
    ZeroExtendedImmediate <= std_logic_vector(resize(unsigned(RawImmediate), 32));
    AluImmediateOperand   <= ZeroExtendedImmediate when ImmediateZeroExtend = '1' else SignExtendedImmediate;

    AluOperandA <= (others => '0') when AluOperandAZero = '1' else RegisterReadData1;
    AluOperandB <= AluImmediateOperand when AluSourceSelect = '1' else RegisterReadData2;

    Alu32Instance: Alu32
        port map (
            OperandA => AluOperandA,
            OperandB => AluOperandB,
            OpCode   => DecodedAluOpCode,
            Result   => AluResult,
            ZeroFlag => AluZeroFlag
        );

    ------------------------------------------------------------------
    -- Memory: address = ALU result (rs + immediate); value written is
    -- always rt, only meaningful when ControlMemoryWriteEnable = '1'.
    ------------------------------------------------------------------
    MemoryAddress <= AluResult(7 downto 0);

    DataMemoryInstance: DataMemory
        port map (
            Clock             => clk,
            Address           => MemoryAddress,
            WriteData         => RegisterReadData2,
            MemoryWriteEnable => ControlMemoryWriteEnable,
            ReadData          => MemoryReadData,
            IoAddress         => ioaddress,
            IoData            => iodata,
            IoEnable          => ioenable
        );

    ------------------------------------------------------------------
    -- Next PC. BranchImmediate is the low 10 bits of the 16-bit immediate;
    -- PcUnit sign-extends it internally.
    ------------------------------------------------------------------
    PcUnitInstance: PcUnit
        port map (
            CurrentProgramCounter => ProgramCounter,
            BranchEnable          => BranchEnable,
            BranchOnZero          => BranchOnZero,
            ZeroFlag              => AluZeroFlag,
            JumpEnable            => JumpEnable,
            BranchImmediate       => RawImmediate(9 downto 0),
            JumpAddress           => JumpAddressField,
            NextProgramCounter    => NextProgramCounter
        );

    ProgramCounterUpdate: process (clk)
    begin
        if rising_edge(clk) then
            ProgramCounter <= NextProgramCounter;
        end if;
    end process;

end Structural;
