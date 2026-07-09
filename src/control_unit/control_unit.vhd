library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Instruction decoder: turns OpCode (+FunctionCode for R-type) into every
-- control signal the datapath needs this cycle. Purely combinational, no
-- computation of its own.
entity ControlUnit is
    Port (
        -- Bits 31-26 of the instruction word; fully identifies I/J-type
        -- instructions, and R-type (OpCode = 0x00, needs FunctionCode too).
        OpCode                    : in  STD_LOGIC_VECTOR (5 downto 0);

        -- Funct field; only meaningful when OpCode = 0x00.
        FunctionCode              : in  STD_LOGIC_VECTOR (2 downto 0);

        -- '1' = write-back address is rd (R-type); '0' = rt (load,
        -- load-immediate).
        RegisterDestinationSelect : out STD_LOGIC;

        -- '1' = ALU's second operand is the extended immediate; '0' = rt.
        AluSourceSelect           : out STD_LOGIC;

        -- Only meaningful when AluSourceSelect = '1'. '1' = zero-extend the
        -- immediate (load-immediate); '0' = sign-extend (load/store address).
        ImmediateZeroExtend       : out STD_LOGIC;

        -- '1' forces the ALU's first operand to zero instead of rs. Needed
        -- for load-immediate: computing "0 OR immediate" lets its result
        -- ride the normal ALU write-back path without a dedicated one, and
        -- can't rely on r0 holding zero since r0 isn't hardwired here.
        AluOperandAZero           : out STD_LOGIC;

        -- '1' = write back DataMemory's read data (load); '0' = ALU result.
        MemoryToRegisterSelect    : out STD_LOGIC;

        RegisterWriteEnable       : out STD_LOGIC;
        MemoryWriteEnable         : out STD_LOGIC;

        -- '1' for beq/bne: this instruction may redirect the PC.
        BranchEnable              : out STD_LOGIC;

        -- Only meaningful when BranchEnable = '1'. '1' = take the branch
        -- when ZeroFlag = '1' (beq); '0' = when ZeroFlag = '0' (bne).
        BranchOnZero              : out STD_LOGIC;

        -- '1' for jump: unconditionally redirect the PC to an absolute address.
        JumpEnable                : out STD_LOGIC;

        -- Alu32's opcode. R-type passes FunctionCode straight through
        -- (same encoding as ALUBitSlice's Opcode); everything else forces
        -- a fixed op: add (000) for load/store address calc, sub (001)
        -- for beq/bne's equality test, or (011) for load-immediate's
        -- zero-operand trick.
        AluOpCode                 : out STD_LOGIC_VECTOR (2 downto 0)
    );
end ControlUnit;

architecture Behavioral of ControlUnit is
begin

    Decode: process (OpCode, FunctionCode)
    begin
        -- Safe defaults so every signal is driven on every path (avoids
        -- inferred latches); also the correct values for instructions that
        -- write no register and touch no memory (store/beq/bne/jump/nop).
        RegisterDestinationSelect <= '0';
        AluSourceSelect           <= '0';
        ImmediateZeroExtend       <= '0';
        AluOperandAZero           <= '0';
        MemoryToRegisterSelect    <= '0';
        RegisterWriteEnable       <= '0';
        MemoryWriteEnable         <= '0';
        BranchEnable              <= '0';
        BranchOnZero              <= '0';
        JumpEnable                <= '0';
        AluOpCode                 <= "000";

        case OpCode is

            -- R-type (add/sub/and/or/xor/not/lbs/inc): both operands from
            -- registers, result always written to rd.
            when "000000" =>
                RegisterDestinationSelect <= '1';
                AluSourceSelect           <= '0';
                MemoryToRegisterSelect    <= '0';
                RegisterWriteEnable       <= '1';
                AluOpCode                 <= FunctionCode;

            -- load immediate (0x22): rt = 0 OR immediate = immediate.
            when "100010" =>
                RegisterDestinationSelect <= '0';
                AluSourceSelect           <= '1';
                ImmediateZeroExtend       <= '1';
                AluOperandAZero           <= '1';
                MemoryToRegisterSelect    <= '0';
                RegisterWriteEnable       <= '1';
                AluOpCode                 <= "011";

            -- load (0x23): rt = mem(rs + immediate).
            when "100011" =>
                RegisterDestinationSelect <= '0';
                AluSourceSelect           <= '1';
                MemoryToRegisterSelect    <= '1';
                RegisterWriteEnable       <= '1';
                AluOpCode                 <= "000";

            -- store (0x21): mem(rs + immediate) = rt. Writes no register.
            when "100001" =>
                AluSourceSelect   <= '1';
                MemoryWriteEnable <= '1';
                AluOpCode         <= "000";

            -- beq (0x05): branch when rs = rt (rs - rt = 0).
            when "000101" =>
                BranchEnable <= '1';
                BranchOnZero <= '1';
                AluOpCode    <= "001";

            -- bne (0x04): branch when rs /= rt (rs - rt /= 0).
            when "000100" =>
                BranchEnable <= '1';
                BranchOnZero <= '0';
                AluOpCode    <= "001";

            -- jump (0x02): unconditional absolute redirect.
            when "000010" =>
                JumpEnable <= '1';

            -- nop (0x3f) and anything unused: defaults already mean "do nothing".
            when others =>
                null;

        end case;
    end process;

end Behavioral;
