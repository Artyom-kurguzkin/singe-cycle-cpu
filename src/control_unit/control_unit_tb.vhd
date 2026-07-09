library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Truth-table testbench for ControlUnit: one assert block per instruction,
-- checking every control output. R-type is checked with several
-- FunctionCode values to confirm AluOpCode passes it straight through.
entity ControlUnit_tb is
end ControlUnit_tb;

architecture Behavioral of ControlUnit_tb is

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

    signal OpCode                    : STD_LOGIC_VECTOR (5 downto 0) := (others => '0');
    signal FunctionCode              : STD_LOGIC_VECTOR (2 downto 0) := (others => '0');
    signal RegisterDestinationSelect : STD_LOGIC;
    signal AluSourceSelect           : STD_LOGIC;
    signal ImmediateZeroExtend       : STD_LOGIC;
    signal AluOperandAZero           : STD_LOGIC;
    signal MemoryToRegisterSelect    : STD_LOGIC;
    signal RegisterWriteEnable       : STD_LOGIC;
    signal MemoryWriteEnable         : STD_LOGIC;
    signal BranchEnable              : STD_LOGIC;
    signal BranchOnZero              : STD_LOGIC;
    signal JumpEnable                : STD_LOGIC;
    signal AluOpCode                 : STD_LOGIC_VECTOR (2 downto 0);

begin

    UnitUnderTest: ControlUnit
        port map (
            OpCode                    => OpCode,
            FunctionCode              => FunctionCode,
            RegisterDestinationSelect => RegisterDestinationSelect,
            AluSourceSelect           => AluSourceSelect,
            ImmediateZeroExtend       => ImmediateZeroExtend,
            AluOperandAZero           => AluOperandAZero,
            MemoryToRegisterSelect    => MemoryToRegisterSelect,
            RegisterWriteEnable       => RegisterWriteEnable,
            MemoryWriteEnable         => MemoryWriteEnable,
            BranchEnable              => BranchEnable,
            BranchOnZero              => BranchOnZero,
            JumpEnable                => JumpEnable,
            AluOpCode                 => AluOpCode
        );

    Stimulus: process
    begin
        -- ---- R-type: add (opcode 0x00, funct 000) ----
        OpCode <= "000000"; FunctionCode <= "000";
        wait for 10 ns; -- let the combinational decode settle
        assert RegisterDestinationSelect = '1' and AluSourceSelect = '0'
            and AluOperandAZero = '0' and MemoryToRegisterSelect = '0'
            and RegisterWriteEnable = '1' and MemoryWriteEnable = '0'
            and BranchEnable = '0' and JumpEnable = '0'
            and AluOpCode = "000"
            report "R-TYPE add DECODE FAILED" severity failure;

        -- ---- R-type: sub (opcode 0x00, funct 001) ----
        -- Same control signals as add above, but AluOpCode must track
        -- FunctionCode -- this is the case that actually proves
        -- pass-through rather than a hardcoded "000".
        OpCode <= "000000"; FunctionCode <= "001";
        wait for 10 ns;
        assert RegisterDestinationSelect = '1' and AluSourceSelect = '0'
            and RegisterWriteEnable = '1' and AluOpCode = "001"
            report "R-TYPE sub DECODE FAILED" severity failure;

        -- ---- R-type: lbs (opcode 0x00, funct 110) ----
        -- A second pass-through check with a different funct value, in
        -- case a case-statement typo happened to match only 000/001.
        OpCode <= "000000"; FunctionCode <= "110";
        wait for 10 ns;
        assert RegisterDestinationSelect = '1' and AluSourceSelect = '0'
            and RegisterWriteEnable = '1' and AluOpCode = "110"
            report "R-TYPE lbs DECODE FAILED" severity failure;

        -- ---- load immediate (0x22) ----
        -- The one case where ImmediateZeroExtend must be '1' -- everything
        -- else in this ISA that uses the immediate wants it sign-extended.
        OpCode <= "100010"; FunctionCode <= "000"; -- funct is a don't-care for I-type
        wait for 10 ns;
        assert RegisterDestinationSelect = '0' and AluSourceSelect = '1'
            and ImmediateZeroExtend = '1' and AluOperandAZero = '1'
            and MemoryToRegisterSelect = '0'
            and RegisterWriteEnable = '1' and MemoryWriteEnable = '0'
            and BranchEnable = '0' and JumpEnable = '0'
            and AluOpCode = "011"
            report "LOAD IMMEDIATE DECODE FAILED" severity failure;

        -- ---- load (0x23) ----
        OpCode <= "100011"; FunctionCode <= "000";
        wait for 10 ns;
        assert RegisterDestinationSelect = '0' and AluSourceSelect = '1'
            and ImmediateZeroExtend = '0' and AluOperandAZero = '0'
            and MemoryToRegisterSelect = '1'
            and RegisterWriteEnable = '1' and MemoryWriteEnable = '0'
            and BranchEnable = '0' and JumpEnable = '0'
            and AluOpCode = "000"
            report "LOAD DECODE FAILED" severity failure;

        -- ---- store (0x21) ----
        OpCode <= "100001"; FunctionCode <= "000";
        wait for 10 ns;
        assert AluSourceSelect = '1' and ImmediateZeroExtend = '0'
            and AluOperandAZero = '0'
            and RegisterWriteEnable = '0' and MemoryWriteEnable = '1'
            and BranchEnable = '0' and JumpEnable = '0'
            and AluOpCode = "000"
            report "STORE DECODE FAILED" severity failure;

        -- ---- beq (0x05) ----
        OpCode <= "000101"; FunctionCode <= "000";
        wait for 10 ns;
        assert AluSourceSelect = '0' and RegisterWriteEnable = '0'
            and MemoryWriteEnable = '0' and BranchEnable = '1'
            and BranchOnZero = '1' and JumpEnable = '0'
            and AluOpCode = "001"
            report "BEQ DECODE FAILED" severity failure;

        -- ---- bne (0x04) ----
        -- Same as beq except BranchOnZero's polarity -- the one bit that
        -- actually distinguishes "branch if equal" from "branch if not
        -- equal" at the control-signal level.
        OpCode <= "000100"; FunctionCode <= "000";
        wait for 10 ns;
        assert AluSourceSelect = '0' and RegisterWriteEnable = '0'
            and MemoryWriteEnable = '0' and BranchEnable = '1'
            and BranchOnZero = '0' and JumpEnable = '0'
            and AluOpCode = "001"
            report "BNE DECODE FAILED" severity failure;

        -- ---- jump (0x02) ----
        OpCode <= "000010"; FunctionCode <= "000";
        wait for 10 ns;
        assert JumpEnable = '1' and RegisterWriteEnable = '0'
            and MemoryWriteEnable = '0' and BranchEnable = '0'
            report "JUMP DECODE FAILED" severity failure;

        -- ---- nop (0x3f) ----
        -- Every output must be inactive/default -- nop does nothing.
        OpCode <= "111111"; FunctionCode <= "000";
        wait for 10 ns;
        assert RegisterDestinationSelect = '0' and AluSourceSelect = '0'
            and ImmediateZeroExtend = '0' and AluOperandAZero = '0'
            and MemoryToRegisterSelect = '0'
            and RegisterWriteEnable = '0' and MemoryWriteEnable = '0'
            and BranchEnable = '0' and BranchOnZero = '0' and JumpEnable = '0'
            and AluOpCode = "000"
            report "NOP DECODE FAILED" severity failure;

        -- ---- An unused/reserved opcode falls through to the same ----
        -- ---- safe "do nothing" defaults as nop ----
        OpCode <= "010101"; FunctionCode <= "000";
        wait for 10 ns;
        assert RegisterWriteEnable = '0' and MemoryWriteEnable = '0'
            and BranchEnable = '0' and JumpEnable = '0'
            report "UNUSED OPCODE DID NOT DEFAULT SAFELY" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
