library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires a real RegisterFile and a real Alu32
-- together and drives them through a short instruction sequence, the same
-- shape of work a single-cycle CPU does for an R-type instruction: read
-- two source registers, feed them through the ALU, write the result back.
--
-- Sequence:
--   r1 <= 5, r2 <= 7          (seed)
--   r3 <= r1 + r2 = 12        (ALU add)
--   r4 <= r3 - r1 = 7         (ALU sub, chains off the previous result)
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

    signal ReadRegisterAddress1 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadRegisterAddress2 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadData1            : STD_LOGIC_VECTOR (31 downto 0);
    signal ReadData2            : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RegisterWriteEnable  : STD_LOGIC := '0';

    signal OpCode                : STD_LOGIC_VECTOR (2 downto 0) := "000";
    signal AluResult             : STD_LOGIC_VECTOR (31 downto 0);

    -- Seed constant or the ALU's result; a real CPU would pick this with a
    -- MemToReg-style mux, driven directly here since there's no control unit.
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

    -- ReadData1/ReadData2 feed straight into OperandA/OperandB -- this is
    -- the actual integration point under test.
    Alu32UnderTest: Alu32
        port map (
            OperandA => ReadData1,
            OperandB => ReadData2,
            OpCode   => OpCode,
            Result   => AluResult,
            ZeroFlag => open
        );

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
        -- ---- r1 <= 5 (seed) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(1, 4));
        WriteDataMux          <= std_logic_vector(to_unsigned(5, 32));
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);

        -- ---- r2 <= 7 (seed) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(2, 4));
        WriteDataMux          <= std_logic_vector(to_unsigned(7, 32));
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- ---- r3 <= r1 + r2 ----
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(1, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(2, 4));
        OpCode                <= "000"; -- add
        wait for 1 ns;
        assert unsigned(AluResult) = 12
            report "INTEGRATION ADD (r1+r2) PRODUCED WRONG RESULT" severity failure;

        WriteRegisterAddress <= std_logic_vector(to_unsigned(3, 4));
        WriteDataMux          <= AluResult;
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- Confirm the write landed and is visible on a read port.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        wait for 1 ns;
        assert unsigned(ReadData1) = 12
            report "INTEGRATION WRITE-BACK OF ADD RESULT FAILED" severity failure;

        -- ---- r4 <= r3 - r1 (chains off the previous result) ----
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
