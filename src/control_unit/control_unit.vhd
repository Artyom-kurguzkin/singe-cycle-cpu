library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- ControlUnit is the instruction decoder: it looks at an instruction's
-- 6-bit OpCode (and, for R-type instructions, its 3-bit FunctionCode) and
-- produces every control signal the rest of the datapath needs to execute
-- that instruction correctly this cycle. Nothing in here does any actual
-- computation (no ALU math, no memory access) -- it only decides *how* the
-- other modules (RegisterFile, Alu32, DataMemory, and eventually PcUnit)
-- should be wired together for the one instruction currently being
-- executed. This is a purely combinational module: for a single-cycle CPU,
-- every one of these signals must be valid within the same cycle the
-- instruction is fetched, with no clock delay.
--
-- One design note beyond the ISA table itself: `load immediate` needs the
-- ALU to compute "zero OP immediate" so its result (the immediate itself)
-- can ride the normal ALU-result write-back path instead of needing a
-- brand new write-back data source. That requires forcing the ALU's first
-- operand to zero -- but this ISA's r0 is an ordinary read/write register,
-- not a hardwired zero constant (see
-- docs/cpu-implementation-plan.md section 2), so relying on "r0 happens to
-- hold zero" would be a fragile, program-specific assumption, not a real
-- hardware guarantee. AluOperandAZero exists specifically to make this
-- correct in general, independent of what any particular program does with
-- r0.
entity ControlUnit is
    Port (
        -- The instruction's opcode field (bits 31 downto 26 of the 32-bit
        -- word -- see docs/cpu-implementation-plan.md section 1's format
        -- tables). This alone fully identifies every I-type and J-type
        -- instruction; only R-type instructions (OpCode = 0x00) need
        -- FunctionCode as well to tell add/sub/and/... apart.
        OpCode                    : in  STD_LOGIC_VECTOR (5 downto 0);

        -- The instruction's funct field (only meaningful when OpCode =
        -- 0x00, i.e. an R-type instruction -- ignored otherwise).
        FunctionCode              : in  STD_LOGIC_VECTOR (2 downto 0);

        -- '1' selects the R-type destination register field (rd) for the
        -- write-back register address; '0' selects the I-type field (rt) --
        -- used by load and load-immediate, which both write back to rt.
        RegisterDestinationSelect : out STD_LOGIC;

        -- '1' selects the sign/zero-extended immediate as the ALU's second
        -- operand; '0' selects the register file's rt read data. Used by
        -- every I-type instruction that needs the ALU (load-immediate,
        -- load, store); R-type instructions always use a register for both
        -- operands.
        AluSourceSelect           : out STD_LOGIC;

        -- '1' forces the ALU's first operand to all-zero instead of the
        -- register file's rs read data -- see this entity's header comment
        -- for why `load immediate` specifically needs this.
        AluOperandAZero           : out STD_LOGIC;

        -- '1' selects DataMemory's read data as the value written back to
        -- the register file; '0' selects the ALU's result. Only `load`
        -- needs memory data; every other register-writing instruction
        -- writes back the ALU's result (including `load immediate`, via
        -- the zero-operand trick above).
        MemoryToRegisterSelect    : out STD_LOGIC;

        -- '1' enables RegisterFile's write port this cycle. Named to match
        -- RegisterFile's own `RegisterWriteEnable` port exactly, so
        -- cpu.vhd can wire this straight across with no renaming.
        RegisterWriteEnable       : out STD_LOGIC;

        -- '1' enables DataMemory's RAM write (and, if the computed address
        -- falls in the IO half, its IoEnable pulse) this cycle. Named to
        -- match DataMemory's own `MemoryWriteEnable` port exactly, for the
        -- same reason as RegisterWriteEnable above.
        MemoryWriteEnable         : out STD_LOGIC;

        -- '1' for beq/bne, telling the (future) PcUnit that this
        -- instruction might redirect the PC to a branch target rather than
        -- just PC+1. Whether it actually does depends on BranchOnZero
        -- below combined with the ALU's ZeroFlag.
        BranchEnable              : out STD_LOGIC;

        -- Only meaningful when BranchEnable = '1'. '1' means "take the
        -- branch when ZeroFlag = '1'" (beq: branch when rs == rt, which the
        -- ALU computes by subtracting rs - rt and checking for a zero
        -- result). '0' means "take the branch when ZeroFlag = '0'" (bne:
        -- branch when rs /= rt). This is the "zero-flag polarity" the
        -- module map (docs/cpu-implementation-plan.md section 3) already
        -- flagged pc_unit.vhd as needing to gate on.
        BranchOnZero              : out STD_LOGIC;

        -- '1' for `jump`, telling the (future) PcUnit to load the
        -- instruction's absolute 10-bit address instead of computing a
        -- sequential or branch target.
        JumpEnable                : out STD_LOGIC;

        -- The opcode fed straight into Alu32. For R-type instructions this
        -- is FunctionCode passed straight through with zero translation
        -- (see docs/cpu-implementation-plan.md section 1: "Funct values for
        -- R-type are identical to ALUBitSlice's Opcode input"). For
        -- everything else, this entity forces a specific ALU operation:
        -- add (000) for load/store address calculation, sub (001) for
        -- beq/bne's equality test, or (011) for load-immediate's
        -- zero-operand pass-through trick.
        AluOpCode                 : out STD_LOGIC_VECTOR (2 downto 0)
    );
end ControlUnit;

architecture Behavioral of ControlUnit is
begin

    Decode: process (OpCode, FunctionCode)
    begin
        -- Every output gets a safe, deterministic default first, so that
        -- no signal is ever left undriven on any path through the case
        -- statement below (VHDL processes must assign every output on
        -- every path or synthesis would infer an unwanted latch -- the
        -- same reasoning ALUBitSlice's process follows). These defaults
        -- also double as the correct values for every instruction that
        -- doesn't write a register or touch memory (store/beq/bne/jump/nop),
        -- for which RegisterDestinationSelect/AluSourceSelect/
        -- AluOperandAZero/MemoryToRegisterSelect/BranchOnZero are genuine
        -- don't-cares per the ISA table.
        RegisterDestinationSelect <= '0';
        AluSourceSelect           <= '0';
        AluOperandAZero           <= '0';
        MemoryToRegisterSelect    <= '0';
        RegisterWriteEnable       <= '0';
        MemoryWriteEnable         <= '0';
        BranchEnable              <= '0';
        BranchOnZero              <= '0';
        JumpEnable                <= '0';
        AluOpCode                 <= "000";

        case OpCode is

            -- R-type (add/sub/and/or/xor/not/lbs/inc): both operands come
            -- from registers, the result always goes to rd, and always
            -- gets written back. FunctionCode selects the actual operation
            -- and is passed straight through to the ALU untranslated.
            when "000000" =>
                RegisterDestinationSelect <= '1'; -- destination is rd
                AluSourceSelect           <= '0'; -- second operand is rt
                MemoryToRegisterSelect    <= '0'; -- write back the ALU result
                RegisterWriteEnable       <= '1';
                AluOpCode                 <= FunctionCode;

            -- load immediate (0x22): compute 0 OR immediate = immediate,
            -- then write that ALU result back to rt. See this entity's
            -- header comment for why AluOperandAZero is needed here.
            when "100010" =>
                RegisterDestinationSelect <= '0'; -- destination is rt
                AluSourceSelect           <= '1'; -- second operand is the immediate
                AluOperandAZero           <= '1'; -- force first operand to zero
                MemoryToRegisterSelect    <= '0'; -- write back the ALU result
                RegisterWriteEnable       <= '1';
                AluOpCode                 <= "011"; -- or: 0 or immediate = immediate

            -- load (0x23): compute address = rs + immediate, read
            -- DataMemory at that address, write the result back to rt.
            when "100011" =>
                RegisterDestinationSelect <= '0'; -- destination is rt
                AluSourceSelect           <= '1'; -- second operand is the immediate
                MemoryToRegisterSelect    <= '1'; -- write back DataMemory's read data
                RegisterWriteEnable       <= '1';
                AluOpCode                 <= "000"; -- add: address = rs + immediate

            -- store (0x21): compute address = rs + immediate, write rt's
            -- value to DataMemory at that address. Never writes a register.
            when "100001" =>
                AluSourceSelect   <= '1'; -- second operand is the immediate
                MemoryWriteEnable <= '1';
                AluOpCode         <= "000"; -- add: address = rs + immediate

            -- beq (0x05): compute rs - rt; branch when the result is zero
            -- (i.e. rs = rt). Never writes a register.
            when "000101" =>
                BranchEnable <= '1';
                BranchOnZero <= '1'; -- take the branch when ZeroFlag = '1'
                AluOpCode    <= "001"; -- sub: ZeroFlag reflects rs = rt

            -- bne (0x04): compute rs - rt; branch when the result is
            -- non-zero (i.e. rs /= rt). Never writes a register.
            when "000100" =>
                BranchEnable <= '1';
                BranchOnZero <= '0'; -- take the branch when ZeroFlag = '0'
                AluOpCode    <= "001"; -- sub: ZeroFlag reflects rs /= rt

            -- jump (0x02): unconditionally redirect the PC to the
            -- instruction's absolute address. Never writes a register or
            -- touches memory, and doesn't need the ALU at all.
            when "000010" =>
                JumpEnable <= '1';

            -- nop (0x3f) and any other/unused opcode: every default above
            -- already describes "do nothing" correctly, so nothing extra
            -- needs setting here.
            when others =>
                null;

        end case;
    end process;

end Behavioral;
