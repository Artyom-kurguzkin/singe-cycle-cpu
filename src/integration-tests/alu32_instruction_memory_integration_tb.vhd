library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: previews the "fetch the next instruction"
-- interaction that the real PC unit (Step 7) and InstructionMemory will
-- have inside cpu.vhd, using the two already-completed modules that make it
-- up -- Alu32 (computing PC + 1 via the `inc` opcode, the same way a
-- single-cycle CPU's next-PC logic does for a plain sequential instruction,
-- no branch/jump taken) and InstructionMemory (fetching whatever
-- instruction sits at the resulting address). There is no dedicated PC
-- register/pc_unit.vhd yet, so this testbench plays that role itself with
-- a plain signal, advanced on each clock edge -- once pc_unit.vhd exists,
-- this same "increment, then fetch" wiring is exactly what it will do
-- internally for the non-branch/non-jump case.
--
-- Modelled sequence: starting at address 0, repeatedly compute
-- CurrentAddress + 1 through the real ALU and fetch through the real
-- instruction memory, checking that addresses 0, 1, 2 come back in order
-- with the exact placeholder words instruction_memory.vhd stores there.
entity Alu32InstructionMemoryIntegrationTb is
end Alu32InstructionMemoryIntegrationTb;

architecture Behavioral of Alu32InstructionMemoryIntegrationTb is

    component Alu32 is
        Port (
            OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
            OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
            OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
            Result   : out STD_LOGIC_VECTOR (31 downto 0);
            ZeroFlag : out STD_LOGIC
        );
    end component;

    component InstructionMemory is
        Port (
            Address        : in  STD_LOGIC_VECTOR (9 downto 0);
            InstructionOut : out STD_LOGIC_VECTOR (31 downto 0)
        );
    end component;

    signal Clock          : STD_LOGIC := '0';
    signal StopClock      : BOOLEAN := false;

    -- Stands in for the not-yet-built PC register: 10 bits wide, matching
    -- InstructionMemory's Address width exactly (see
    -- instruction_memory.vhd's comment on why that width was chosen).
    signal CurrentAddress : STD_LOGIC_VECTOR (9 downto 0) := (others => '0');

    -- Alu32 signals. OperandA is CurrentAddress zero-extended to 32 bits
    -- (the ALU is always 32 bits wide regardless of what it's being used
    -- to compute); OperandB is unused by the inc opcode so it is tied to
    -- all zeros.
    signal AluOperandA    : STD_LOGIC_VECTOR (31 downto 0);
    signal AluResult      : STD_LOGIC_VECTOR (31 downto 0);

    -- The fetched instruction word, read out of InstructionMemory at
    -- whatever address CurrentAddress currently holds.
    signal FetchedInstruction : STD_LOGIC_VECTOR (31 downto 0);

begin

    -- Zero-extend the 10-bit address into the ALU's 32-bit operand width.
    -- Using resize() rather than a hand-written zero-padding literal avoids
    -- an off-by-one in the pad width (32 - 10 = 22 zero bits -- easy to
    -- miscount by hand, which is exactly what happened here originally).
    -- Both widths (CurrentAddress's fixed 10 bits, the literal 32) are
    -- compile-time constants, so this is ordinary fixed-width hardware, not
    -- runtime-variable sizing.
    AluOperandA <= STD_LOGIC_VECTOR(resize(unsigned(CurrentAddress), 32));

    Alu32UnderTest: Alu32
        port map (
            OperandA => AluOperandA,
            OperandB => (others => '0'),
            OpCode   => "111", -- inc: computes CurrentAddress + 1
            Result   => AluResult,
            ZeroFlag => open
        );

    InstructionMemoryUnderTest: InstructionMemory
        port map (
            Address        => CurrentAddress,
            InstructionOut => FetchedInstruction
        );

    -- A free-running clock, needed to advance CurrentAddress the same way
    -- a real PC register advances once per instruction.
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

    -- Advances CurrentAddress to the ALU's computed "+1" result on every
    -- rising edge -- standing in for a real PC register's clocked update,
    -- which pc_unit.vhd + a PC register in cpu.vhd will do for real once
    -- they exist.
    AddressAdvance: process (Clock)
    begin
        if rising_edge(Clock) then
            CurrentAddress <= AluResult(9 downto 0);
        end if;
    end process;

    Stimulus: process
    begin
        -- ---- Address 0 (the starting address, before any clock edge) ----
        wait for 1 ns; -- let the async ALU + instruction memory settle
        assert FetchedInstruction = x"11111111"
            report "FETCH AT ADDRESS 0 FAILED" severity failure;

        -- ---- Address 1, reached via one ALU-computed increment ----
        wait until rising_edge(Clock);
        wait for 1 ns;
        assert unsigned(CurrentAddress) = 1
            report "ALU DID NOT ADVANCE ADDRESS TO 1" severity failure;
        assert FetchedInstruction = x"22222222"
            report "FETCH AT ADDRESS 1 FAILED" severity failure;

        -- ---- Address 2, reached via a second ALU-computed increment ----
        wait until rising_edge(Clock);
        wait for 1 ns;
        assert unsigned(CurrentAddress) = 2
            report "ALU DID NOT ADVANCE ADDRESS TO 2" severity failure;
        assert FetchedInstruction = x"33333333"
            report "FETCH AT ADDRESS 2 FAILED" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
