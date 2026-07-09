library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Next-PC mux: given the current PC and ControlUnit's decode of the
-- current instruction, computes what the PC should become next --
-- sequential (+1), a taken branch (+signed offset), or an absolute jump.
-- Purely combinational; the actual PC register lives in cpu.vhd.
entity PcUnit is
    Port (
        -- Word-addressed (not byte-addressed), 10 bits for a 1024-word
        -- instruction memory.
        CurrentProgramCounter : in  STD_LOGIC_VECTOR (9 downto 0);

        -- '1' when the current instruction is beq/bne.
        BranchEnable          : in  STD_LOGIC;

        -- Zero-flag polarity that takes the branch: '1' = take when
        -- ZeroFlag='1' (beq), '0' = take when ZeroFlag='0' (bne).
        BranchOnZero          : in  STD_LOGIC;

        -- From Alu32: reflects rs - rt = 0 (ControlUnit forces subtract
        -- for beq/bne so this means rs = rt).
        ZeroFlag              : in  STD_LOGIC;

        -- '1' when the current instruction is `jump`.
        JumpEnable            : in  STD_LOGIC;

        -- Raw (not yet sign-extended) 10-bit branch offset field.
        BranchImmediate       : in  STD_LOGIC_VECTOR (9 downto 0);

        -- Absolute jump target, used directly with no arithmetic.
        JumpAddress           : in  STD_LOGIC_VECTOR (9 downto 0);

        -- What the PC register should latch next clock edge.
        NextProgramCounter    : out STD_LOGIC_VECTOR (9 downto 0)
    );
end PcUnit;

architecture Behavioral of PcUnit is

    -- +1, sequential case. Extra bit of headroom avoids overflow
    -- detection at the max 10-bit value; truncating back to 10 bits below
    -- wraps the same way a fixed-width register would.
    signal SequentialProgramCounter : unsigned (10 downto 0);

    -- +sign_extend(BranchImmediate), for a taken branch (may go backwards).
    signal BranchTargetProgramCounter : signed (10 downto 0);

    -- '1' when BranchEnable is set and ZeroFlag matches BranchOnZero's
    -- polarity. xnor captures both beq/bne cases in one STD_LOGIC bit
    -- (plain "=" would return a BOOLEAN, which can't "and" with BranchEnable).
    signal BranchTaken : STD_LOGIC;

begin

    SequentialProgramCounter   <= resize(unsigned(CurrentProgramCounter), 11) + 1;
    BranchTargetProgramCounter <= resize(signed(CurrentProgramCounter), 11) + resize(signed(BranchImmediate), 11);

    BranchTaken <= BranchEnable and (ZeroFlag xnor BranchOnZero);

    -- Priority: jump, then taken branch, then sequential. At most one of
    -- JumpEnable/BranchTaken is ever '1' in the same cycle regardless.
    NextProgramCounter <= JumpAddress when JumpEnable = '1' else
                          std_logic_vector(BranchTargetProgramCounter(9 downto 0)) when BranchTaken = '1' else
                          std_logic_vector(SequentialProgramCounter(9 downto 0));

end Behavioral;
