library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires real RegisterFile, Alu32, and DataMemory
-- together and drives them through the shape of `store`/`load`
-- instructions -- computing an address via the ALU (rs + immediate, op
-- forced to add), exercising DataMemory at that address, then writing a
-- loaded value back into the register file.
--
-- Sequence:
--   r1 <= 20, r2 <= 0xCAFEBABE            (seed base address, data)
--   mem(r1 + 5) <= r2                     (store)
--   r3 <= mem(r1 + 5); assert r3 = r2     (load, round trip)
--   mem(r1 + 110) <= r2                   (address 130, falls in IO half)
--   assert IoEnable pulsed correctly, and RAM at aliased index 2 untouched
entity RegisterFileAlu32DataMemoryIntegrationTb is
end RegisterFileAlu32DataMemoryIntegrationTb;

architecture Behavioral of RegisterFileAlu32DataMemoryIntegrationTb is

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

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    signal ReadRegisterAddress1 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadRegisterAddress2 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RegisterReadData1    : STD_LOGIC_VECTOR (31 downto 0);
    signal RegisterReadData2    : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RegisterWriteEnable  : STD_LOGIC := '0';

    -- Either a seed constant or DataMemory's ReadData for the load-shaped
    -- step; a real CPU would pick this with a MemToReg mux (no control
    -- unit here, so driven directly).
    signal RegisterWriteDataMux : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

    -- OperandA is always rs; OperandB is the immediate, driven directly by
    -- the stimulus process.
    signal AddressImmediate : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal AluResult        : STD_LOGIC_VECTOR (31 downto 0);

    -- Address truncated from the ALU's 32-bit result to DataMemory's 8-bit bus.
    signal MemoryAddress         : STD_LOGIC_VECTOR (7 downto 0);
    signal MemoryWriteEnable     : STD_LOGIC := '0';
    signal MemoryReadData        : STD_LOGIC_VECTOR (31 downto 0);
    signal IoAddress             : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData                : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable               : STD_LOGIC;

begin

    RegisterFileUnderTest: RegisterFile
        port map (
            Clock                => Clock,
            ReadRegisterAddress1 => ReadRegisterAddress1,
            ReadRegisterAddress2 => ReadRegisterAddress2,
            ReadData1            => RegisterReadData1,
            ReadData2            => RegisterReadData2,
            WriteRegisterAddress => WriteRegisterAddress,
            WriteData            => RegisterWriteDataMux,
            RegisterWriteEnable  => RegisterWriteEnable
        );

    -- OpCode hardwired to add, matching how the real control unit forces
    -- ALU op to add for load/store address calculation.
    Alu32UnderTest: Alu32
        port map (
            OperandA => RegisterReadData1,
            OperandB => AddressImmediate,
            OpCode   => "000",
            Result   => AluResult,
            ZeroFlag => open
        );

    MemoryAddress <= AluResult(7 downto 0);

    -- WriteData is always rt; unused (harmless) during the load-shaped
    -- step, which drives MemoryWriteEnable='0' instead.
    DataMemoryUnderTest: DataMemory
        port map (
            Clock             => Clock,
            Address           => MemoryAddress,
            WriteData         => RegisterReadData2,
            MemoryWriteEnable => MemoryWriteEnable,
            ReadData          => MemoryReadData,
            IoAddress         => IoAddress,
            IoData            => IoData,
            IoEnable          => IoEnable
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
        -- ---- r1 <= 20 (seed base address) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(1, 4));
        RegisterWriteDataMux  <= std_logic_vector(to_unsigned(20, 32));
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);

        -- ---- r2 <= 0xCAFEBABE (seed data to store) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(2, 4));
        RegisterWriteDataMux  <= x"CAFEBABE";
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- ---- mem(r1 + 5) <= r2 (store) ----
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(1, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(2, 4));
        AddressImmediate      <= std_logic_vector(to_unsigned(5, 32));
        MemoryWriteEnable     <= '1';
        wait for 1 ns;
        assert unsigned(AluResult) = 25
            report "INTEGRATION ADDRESS CALC (r1+5) PRODUCED WRONG RESULT" severity failure;
        wait until rising_edge(Clock);
        MemoryWriteEnable <= '0';

        -- ---- r3 <= mem(r1 + 5) (load; same address as the store above) ----
        AddressImmediate <= std_logic_vector(to_unsigned(5, 32));
        wait for 1 ns;
        assert MemoryReadData = x"CAFEBABE"
            report "INTEGRATION LOAD READ BACK WRONG DATA" severity failure;

        WriteRegisterAddress <= std_logic_vector(to_unsigned(3, 4));
        RegisterWriteDataMux  <= MemoryReadData;
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- Round trip: read r3 back through the register file's own read
        -- port, proving the value survived being latched, not just that
        -- DataMemory's output was momentarily correct.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        wait for 1 ns;
        assert RegisterReadData1 = x"CAFEBABE"
            report "INTEGRATION STORE-THEN-LOAD ROUND TRIP FAILED" severity failure;

        -- ---- mem(r1 + 110) <= r2; address 130 falls in the IO half ----
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(1, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(2, 4));
        AddressImmediate      <= std_logic_vector(to_unsigned(110, 32));
        MemoryWriteEnable     <= '1';
        wait for 1 ns;
        assert unsigned(AluResult) = 130
            report "INTEGRATION ADDRESS CALC (r1+110) PRODUCED WRONG RESULT" severity failure;
        assert IoEnable = '1'
            and IoAddress = std_logic_vector(to_unsigned(130, 8))
            and IoData = x"CAFEBABE"
            report "INTEGRATION IO-RANGE STORE DID NOT RAISE IoEnable CORRECTLY" severity failure;
        wait until rising_edge(Clock);
        MemoryWriteEnable <= '0';

        -- The IO-range store above must not have corrupted RAM at the
        -- aliased index (130 - 128 = 2). r0 is still zero (never written),
        -- so using it as rs reaches address 2 with an unsigned immediate.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(0, 4));
        AddressImmediate      <= std_logic_vector(to_unsigned(2, 32));
        MemoryWriteEnable     <= '0';
        wait for 1 ns;
        assert unsigned(MemoryReadData) = 0
            report "INTEGRATION IO-RANGE STORE INCORRECTLY WROTE THROUGH TO ALIASED RAM ADDRESS" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
