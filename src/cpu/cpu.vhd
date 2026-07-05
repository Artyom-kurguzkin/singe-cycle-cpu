library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Cpu is the top-level entity: it structurally wires together every module
-- built in Steps 2-7 (Alu32, RegisterFile, InstructionMemory, DataMemory,
-- ControlUnit, PcUnit) plus the two pieces of state that don't belong to
-- any of those modules on their own -- the PC register itself, and the
-- instruction-field extraction/sign-extension logic that turns a raw
-- 32-bit fetched instruction into the individual signals every other
-- module needs. Every integration test in this project (see
-- src/integration-tests/) has already exercised these same modules
-- cooperating pairwise or in small groups; this entity is where all of
-- that finally comes together into one real, complete single-cycle CPU.
--
-- Ports are named exactly as the spec mandates (lowercase clk/ioaddress/
-- iodata/ioenable) rather than following this project's usual full-name
-- convention (section 0b) -- this is a fixed external interface dictated
-- by the assignment, not a name this project gets to choose, the same
-- exception already carved out for wiring to fixed component interfaces.
entity Cpu is
    Port (
        -- The CPU's single clock. There is no reset pin (per spec) -- the
        -- PC register and RegisterFile/DataMemory's contents all get their
        -- t=0 value from VHDL signal initializers instead, the same
        -- simulation-only approach used throughout this project (see
        -- docs/cpu-implementation-plan.md section 2).
        clk       : in  STD_LOGIC;

        -- Wired straight through from DataMemory's own IoAddress/IoData/
        -- IoEnable ports (see data_memory.vhd) -- per spec, "Your CPU
        -- component should include ports connecting these signals to a
        -- toplevel component, but the IO registers themselves do not need
        -- to be implemented." Meaningful only while ioenable = '1', which
        -- happens for exactly one clock cycle per `store` instruction that
        -- targets the memory-mapped IO half of the address space (128-255).
        ioaddress : out STD_LOGIC_VECTOR (7 downto 0);
        iodata    : out STD_LOGIC_VECTOR (31 downto 0);
        ioenable  : out STD_LOGIC
    );
end Cpu;

architecture Structural of Cpu is

    component InstructionMemory is
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

    -- The one piece of CPU state that doesn't belong to any single module:
    -- the program counter itself. PcUnit only computes what it should
    -- become next (see pc_unit.vhd's header comment); this register is
    -- what actually remembers it between cycles. Initialised to zero via a
    -- signal initializer rather than a reset pin, per spec.
    signal ProgramCounter     : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');
    signal NextProgramCounter : STD_LOGIC_VECTOR (9 downto 0);

    -- The instruction fetched this cycle, and the individual fields
    -- extracted from it. Field bit positions come directly from
    -- docs/cpu-implementation-plan.md section 1's R/I/J format tables --
    -- note that OpCode/rs/rt occupy the same bit positions in every
    -- format, which is exactly what lets ControlUnit start decoding
    -- (OpCode) before the CPU even knows which format the instruction is.
    signal FetchedInstruction : STD_LOGIC_VECTOR (31 downto 0);
    signal InstructionOpCode  : STD_LOGIC_VECTOR (5 downto 0);
    signal RsField            : STD_LOGIC_VECTOR (3 downto 0);
    signal RtField            : STD_LOGIC_VECTOR (3 downto 0);
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

    -- RegisterFile's read outputs and its write-side muxes.
    signal RegisterReadData1    : STD_LOGIC_VECTOR (31 downto 0);
    signal RegisterReadData2    : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0);
    signal RegisterWriteDataMux : STD_LOGIC_VECTOR (31 downto 0);

    -- The immediate field, extended to 32 bits both ways -- see
    -- control_unit.vhd's header comment (note 2) for why `load immediate`
    -- needs zero-extension while `load`/`store` address calculation needs
    -- sign-extension, and why ImmediateZeroExtend is what picks between
    -- them here.
    signal SignExtendedImmediate : STD_LOGIC_VECTOR (31 downto 0);
    signal ZeroExtendedImmediate : STD_LOGIC_VECTOR (31 downto 0);
    signal AluImmediateOperand   : STD_LOGIC_VECTOR (31 downto 0);

    -- Alu32's actual operands (after the AluOperandAZero / AluSourceSelect
    -- muxes) and its outputs.
    signal AluOperandA : STD_LOGIC_VECTOR (31 downto 0);
    signal AluOperandB : STD_LOGIC_VECTOR (31 downto 0);
    signal AluResult   : STD_LOGIC_VECTOR (31 downto 0);
    signal AluZeroFlag : STD_LOGIC;

    -- DataMemory's address (truncated from the ALU's 32-bit result down to
    -- the 8-bit address bus -- addresses only span 0-255) and read output.
    signal MemoryAddress  : STD_LOGIC_VECTOR (7 downto 0);
    signal MemoryReadData : STD_LOGIC_VECTOR (31 downto 0);

begin

    ------------------------------------------------------------------
    -- Fetch: read the instruction at the current PC.
    ------------------------------------------------------------------
    InstructionMemoryInstance: InstructionMemory
        port map (
            Address        => ProgramCounter,
            InstructionOut => FetchedInstruction
        );

    ------------------------------------------------------------------
    -- Decode: split the fetched word into its fields. OpCode/rs/rt sit at
    -- the same bit positions regardless of format; rd/FunctionCode
    -- (R-format), RawImmediate (I-format), and JumpAddressField (J-format)
    -- are only meaningful for instructions that actually use that format,
    -- but extracting them unconditionally is harmless -- whichever ones
    -- don't apply to the current instruction are simply never selected by
    -- any downstream mux.
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
    -- Register read: rs/rt are read every cycle regardless of instruction
    -- type (harmless for instructions that don't need them, e.g. `jump`).
    -- The write side is set up here but only actually commits on the next
    -- rising edge, and only when ControlRegisterWriteEnable is asserted.
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
    -- Execute: sign/zero-extend the immediate, mux the ALU's operands, and
    -- run the ALU.
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
    -- Memory: address comes from the ALU result (rs + immediate); the
    -- value written is always rt (only meaningful when
    -- ControlMemoryWriteEnable = '1', i.e. an actual `store`).
    -- IoAddress/IoData/IoEnable are wired straight through to this
    -- entity's own ioaddress/iodata/ioenable ports.
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
    -- Next PC: compute what the PC should become, then latch it on the
    -- next rising edge. BranchImmediate is the low 10 bits of the 16-bit
    -- immediate field, per the ISA table's beq/bne semantics ("pc +=
    -- sign_extend(immediate(9 downto 0))") -- PcUnit does that
    -- sign-extension itself internally.
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
