library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- PcUnit is the "next PC" mux: given the current program counter and the
-- control signals ControlUnit produced for the instruction currently
-- executing, it decides what the PC should become on the *next* clock
-- edge -- sequential (+1), a taken branch (PC + signed branch offset), or
-- an absolute jump. It contains no register itself: the actual PC register
-- (the thing that latches this value on the clock edge) lives in cpu.vhd
-- (Step 8), the same way Alu32 computes a result but never stores it
-- anywhere on its own. This mirrors a real single-cycle MIPS datapath,
-- where "next-PC logic" and "the PC register" are always two separate
-- pieces -- the logic is purely combinational so it can produce this
-- cycle's answer before the next clock edge even arrives.
entity PcUnit is
    Port (
        -- The current value of the (external) PC register. 10 bits wide
        -- because the CPU is word-addressed with a 1024-word instruction
        -- memory (see docs/cpu-implementation-plan.md section 2: "PC is
        -- word-addressed, not byte-addressed" -- no x4 shift needed
        -- anywhere in this unit, unlike a textbook byte-addressed MIPS).
        CurrentProgramCounter : in  STD_LOGIC_VECTOR (9 downto 0);

        -- From ControlUnit: '1' when the current instruction is beq/bne
        -- (see control_unit.vhd).
        BranchEnable          : in  STD_LOGIC;

        -- From ControlUnit: the zero-flag polarity that actually takes the
        -- branch -- '1' for beq (take it when ZeroFlag = '1'), '0' for bne
        -- (take it when ZeroFlag = '0'). See control_unit.vhd's own
        -- comment on this signal for the full reasoning.
        BranchOnZero          : in  STD_LOGIC;

        -- From Alu32: reflects whether rs - rt was zero (i.e. rs = rt) --
        -- ControlUnit forces AluOpCode to subtract for beq/bne specifically
        -- so this flag means what PcUnit needs it to mean.
        ZeroFlag              : in  STD_LOGIC;

        -- From ControlUnit: '1' when the current instruction is `jump`.
        JumpEnable            : in  STD_LOGIC;

        -- The instruction's raw 10-bit branch-offset field (immediate bits
        -- 9 downto 0, per the ISA table's beq/bne semantics: "pc +=
        -- sign_extend(immediate(9 downto 0))"). PcUnit does the sign
        -- extension itself below; this input is the not-yet-extended bits
        -- straight out of the instruction word.
        BranchImmediate       : in  STD_LOGIC_VECTOR (9 downto 0);

        -- The instruction's 10-bit absolute jump target field, used
        -- directly with no arithmetic at all (per the ISA table: "$pc =
        -- jump target").
        JumpAddress           : in  STD_LOGIC_VECTOR (9 downto 0);

        -- What the PC register in cpu.vhd should latch on the next clock
        -- edge.
        NextProgramCounter    : out STD_LOGIC_VECTOR (9 downto 0)
    );
end PcUnit;

architecture Behavioral of PcUnit is

    -- CurrentProgramCounter + 1, for the ordinary (no branch taken, no
    -- jump) case. Computed with one extra bit of headroom (11 bits) purely
    -- to avoid NUMERIC_STD's unsigned overflow detection tripping if
    -- CurrentProgramCounter is already the maximum 10-bit value (1023);
    -- truncating the 11-bit sum back down to 10 bits below then wraps
    -- exactly the way a fixed-width hardware register naturally would.
    signal SequentialProgramCounter : unsigned (10 downto 0);

    -- CurrentProgramCounter + sign_extend(BranchImmediate), for a taken
    -- branch. Same one-extra-bit-of-headroom reasoning as above, except
    -- here it also has to accommodate BranchImmediate being negative
    -- (branching backwards to an earlier instruction, e.g. a loop).
    signal BranchTargetProgramCounter : signed (10 downto 0);

    -- '1' exactly when a branch instruction's condition is satisfied:
    -- BranchEnable is set (this is actually beq/bne) *and* ZeroFlag
    -- matches the polarity BranchOnZero asked for. XNOR-ing the two
    -- STD_LOGIC bits ("ZeroFlag xnor BranchOnZero") elegantly captures both
    -- polarities at once as a single STD_LOGIC bit (ordinary "=" on two
    -- STD_LOGIC values returns a BOOLEAN, which "and" can't combine with
    -- BranchEnable directly): for beq (BranchOnZero='1'), the xnor is '1'
    -- exactly when ZeroFlag='1'; for bne (BranchOnZero='0'), it's '1'
    -- exactly when ZeroFlag='0'.
    signal BranchTaken : STD_LOGIC;

begin

    SequentialProgramCounter   <= resize(unsigned(CurrentProgramCounter), 11) + 1;
    BranchTargetProgramCounter <= resize(signed(CurrentProgramCounter), 11) + resize(signed(BranchImmediate), 11);

    BranchTaken <= BranchEnable and (ZeroFlag xnor BranchOnZero);

    -- Priority is written as jump, then taken-branch, then sequential --
    -- though in practice at most one of JumpEnable/BranchTaken is ever '1'
    -- at a time anyway, since ControlUnit only asserts one instruction's
    -- worth of control signals per cycle and no opcode is both a jump and
    -- a branch.
    NextProgramCounter <= JumpAddress when JumpEnable = '1' else
                          std_logic_vector(BranchTargetProgramCounter(9 downto 0)) when BranchTaken = '1' else
                          std_logic_vector(SequentialProgramCounter(9 downto 0));

end Behavioral;
