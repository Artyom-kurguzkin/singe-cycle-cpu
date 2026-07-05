library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for DataMemory. Covers: ordinary RAM read/write
-- (ignored without MemoryWriteEnable, captured on the next rising edge with
-- it), an IO-range store correctly raising IoEnable with the right
-- IoAddress/IoData, and -- the specific bug the RAM-write's
-- "IsIoAddress = '0'" guard exists to prevent -- an IO-range store *not*
-- also corrupting the RAM word at the aliased low-7-bits address.
entity DataMemory_tb is
end DataMemory_tb;

architecture Behavioral of DataMemory_tb is

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

    signal Clock             : STD_LOGIC := '0';
    signal StopClock         : BOOLEAN := false;
    signal Address           : STD_LOGIC_VECTOR (7 downto 0) := (others => '0');
    signal WriteData         : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal MemoryWriteEnable : STD_LOGIC := '0';
    signal ReadData          : STD_LOGIC_VECTOR (31 downto 0);
    signal IoAddress         : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData            : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable          : STD_LOGIC;

begin

    UnitUnderTest: DataMemory
        port map (
            Clock             => Clock,
            Address           => Address,
            WriteData         => WriteData,
            MemoryWriteEnable => MemoryWriteEnable,
            ReadData          => ReadData,
            IoAddress         => IoAddress,
            IoData            => IoData,
            IoEnable          => IoEnable
        );

    -- A free-running clock, needed because the RAM write port is
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
        -- ---- RAM read of an untouched address returns zero ----
        -- (relies on Ram's signal initializer, the same t=0-initial-value
        -- approach used throughout this simulation-only project).
        Address <= std_logic_vector(to_unsigned(10, 8));
        wait for 1 ns; -- let the async RAM read settle
        assert unsigned(ReadData) = 0
            report "INITIAL RAM READ NOT ZERO" severity failure;

        -- ---- A RAM store with MemoryWriteEnable='0' is ignored ----
        Address           <= std_logic_vector(to_unsigned(10, 8));
        WriteData         <= x"AAAAAAAA";
        MemoryWriteEnable <= '0';
        wait until rising_edge(Clock);
        wait for 1 ns;
        assert unsigned(ReadData) = 0
            report "RAM WRITE WITHOUT ENABLE WAS CAPTURED" severity failure;

        -- ---- A RAM store with MemoryWriteEnable='1' is captured and ----
        -- ---- reads back correctly on the next cycle ----
        MemoryWriteEnable <= '1';
        wait until rising_edge(Clock);
        MemoryWriteEnable <= '0';
        wait for 1 ns;
        assert ReadData = x"AAAAAAAA"
            report "RAM WRITE-THEN-READBACK FAILED" severity failure;

        -- ---- An ordinary RAM-range store must not raise IoEnable ----
        -- (address 10 is well within the 0-127 RAM half).
        assert IoEnable = '0'
            report "RAM STORE INCORRECTLY RAISED IoEnable" severity failure;

        -- ---- An IO-range store raises IoEnable with the right ----
        -- ---- IoAddress/IoData, combinationally (no clock edge needed) ----
        -- Address 200 = 128 + 72, i.e. bit 7 set -> IO half, aliased RAM
        -- index 72 (200 mod 128).
        Address           <= std_logic_vector(to_unsigned(200, 8));
        WriteData         <= x"12345678";
        MemoryWriteEnable <= '1';
        wait for 1 ns;
        assert IoEnable = '1' and IoAddress = std_logic_vector(to_unsigned(200, 8)) and IoData = x"12345678"
            report "IO-RANGE STORE DID NOT RAISE IoEnable CORRECTLY" severity failure;

        -- ---- The same IO-range store must NOT corrupt RAM at the ----
        -- ---- aliased address (72) ---- this is the exact bug the
        -- IsIoAddress guard in the RAM write process exists to prevent.
        wait until rising_edge(Clock);
        MemoryWriteEnable <= '0';
        Address           <= std_logic_vector(to_unsigned(72, 8)); -- a genuine RAM read of the aliased index
        wait for 1 ns;
        assert unsigned(ReadData) = 0
            report "IO-RANGE STORE INCORRECTLY WROTE THROUGH TO ALIASED RAM ADDRESS" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
