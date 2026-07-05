library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires a real RegisterFile and a real Alu32
-- together (no mocking of either) and drives them through a short
-- hand-written instruction sequence, the same shape of work a single-cycle
-- CPU actually does for an R-type instruction: read two source registers,
-- feed them through the ALU, write the result back to a destination
-- register. This exists to catch integration bugs (mismatched widths,
-- wrong operand ordering, a write that doesn't actually reach the read
-- ports next cycle, etc.) *before* those two modules get buried inside the
-- full cpu.vhd top level, where a bug here would be much harder to isolate.
--
-- Modelled sequence (register numbers are arbitrary, chosen to avoid
-- colliding with each other):
--   r1 <= 5                      (seed)
--   r2 <= 7                      (seed)
--   r3 <= r1 + r2   = 12         (ALU add, mimics "add r3 r1 r2")
--   r4 <= r3 - r1   = 7          (ALU sub, mimics "sub r4 r3 r1", chains
--                                  off the previous instruction's result)
entity RegisterFileAlu32IntegrationTb is
end RegisterFileAlu32IntegrationTb;

architecture Behavioral of RegisterFileAlu32IntegrationTb is

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

    signal Clock                : STD_LOGIC := '0';
    signal StopClock            : BOOLEAN := false;

    -- RegisterFile signals.
    signal ReadRegisterAddress1 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadRegisterAddress2 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadData1            : STD_LOGIC_VECTOR (31 downto 0);
    signal ReadData2            : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RegisterWriteEnable  : STD_LOGIC := '0';

    -- Alu32 signals. Note ReadData1/ReadData2 feed straight into
    -- Alu32's OperandA/OperandB below -- this is the actual integration
    -- point being tested, not just two modules simulated side by side.
    signal OpCode                : STD_LOGIC_VECTOR (2 downto 0) := "000";
    signal AluResult             : STD_LOGIC_VECTOR (31 downto 0);

    -- What ultimately gets written back into the register file: either a
    -- seed constant (for the first two "instructions" below) or the ALU's
    -- result (for the two ALU-driven "instructions"). A real CPU would pick
    -- this with a MemToReg-style mux in the write-back stage; this
    -- testbench drives WriteDataMux directly since there is no control unit
    -- yet to generate that mux's select signal.
    signal WriteDataMux          : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

begin

    RegisterFileUnderTest: RegisterFile
        port map (
            Clock                => Clock,
            ReadRegisterAddress1 => ReadRegisterAddress1,
            ReadRegisterAddress2 => ReadRegisterAddress2,
            ReadData1            => ReadData1,
            ReadData2            => ReadData2,
            WriteRegisterAddress => WriteRegisterAddress,
            WriteData            => WriteDataMux,
            RegisterWriteEnable  => RegisterWriteEnable
        );

    Alu32UnderTest: Alu32
        port map (
            OperandA => ReadData1,
            OperandB => ReadData2,
            OpCode   => OpCode,
            Result   => AluResult,
            ZeroFlag => open
        );

    -- A free-running clock, needed because RegisterFile's write port is
    -- synchronous.
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
        -- ---- "instruction" 1: r1 <= 5 (seed, no ALU involvement) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(1, 4));
        WriteDataMux          <= std_logic_vector(to_unsigned(5, 32));
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);

        -- ---- "instruction" 2: r2 <= 7 (seed, no ALU involvement) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(2, 4));
        WriteDataMux          <= std_logic_vector(to_unsigned(7, 32));
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- ---- "instruction" 3: r3 <= r1 + r2 (mimics "add r3 r1 r2") ----
        -- Point the register file's two read ports at r1/r2; ReadData1/
        -- ReadData2 flow straight into Alu32's operands (see the port map
        -- above), so AluResult should already be settled well before the
        -- next rising edge.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(1, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(2, 4));
        OpCode                <= "000"; -- add
        wait for 1 ns; -- let the async read ports + combinational ALU settle
        assert unsigned(AluResult) = 12
            report "INTEGRATION ADD (r1+r2) PRODUCED WRONG RESULT" severity failure;

        WriteRegisterAddress <= std_logic_vector(to_unsigned(3, 4));
        WriteDataMux          <= AluResult;
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- Confirm the write from "instruction" 3 actually landed and is
        -- visible on a read port on the next cycle -- this is the crux of
        -- the integration test: the ALU's *combinational* result has to
        -- survive being latched into the register file and read back out
        -- again through the *same* dual-read-port hardware used above.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        wait for 1 ns;
        assert unsigned(ReadData1) = 12
            report "INTEGRATION WRITE-BACK OF ADD RESULT FAILED" severity failure;

        -- ---- "instruction" 4: r4 <= r3 - r1 (mimics "sub r4 r3 r1") ----
        -- Chains directly off the previous "instruction"'s result (r3),
        -- proving a computed-and-stored value can be read back out and fed
        -- into a second ALU operation, not just a hand-seeded constant.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(1, 4));
        OpCode                <= "001"; -- sub
        wait for 1 ns;
        assert unsigned(AluResult) = 7
            report "INTEGRATION SUB (r3-r1) PRODUCED WRONG RESULT" severity failure;

        WriteRegisterAddress <= std_logic_vector(to_unsigned(4, 4));
        WriteDataMux          <= AluResult;
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(4, 4));
        wait for 1 ns;
        assert unsigned(ReadData1) = 7
            report "INTEGRATION WRITE-BACK OF SUB RESULT FAILED" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
