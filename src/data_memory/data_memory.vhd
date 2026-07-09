library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Data memory with a memory-mapped IO split: addresses 0-127 are RAM,
-- 128-255 are external IO. IO registers themselves aren't implemented
-- here; this module only detects an IO-range store and exposes it on
-- IoAddress/IoData/IoEnable for something external to observe.
entity DataMemory is
    Port (
        Clock             : in  STD_LOGIC;

        -- 8 bits covers 0-255; bit 7 alone decides RAM vs IO (0-127 has
        -- bit 7 = '0', 128-255 has bit 7 = '1'). Bits 6-0 index the RAM.
        Address           : in  STD_LOGIC_VECTOR (7 downto 0);
        WriteData         : in  STD_LOGIC_VECTOR (31 downto 0);
        MemoryWriteEnable : in  STD_LOGIC;

        -- Valid for RAM addresses (0-127); don't-care for IO addresses.
        ReadData          : out STD_LOGIC_VECTOR (31 downto 0);

        -- Combinational pass-through of an IO-range store.
        IoAddress         : out STD_LOGIC_VECTOR (7 downto 0);
        IoData            : out STD_LOGIC_VECTOR (31 downto 0);
        IoEnable          : out STD_LOGIC
    );
end DataMemory;

architecture Behavioral of DataMemory is

    type RamArrayType is array (0 to 127) of STD_LOGIC_VECTOR (31 downto 0);
    signal Ram : RamArrayType := (others => (others => '0'));

    signal IsIoAddress : STD_LOGIC;

begin

    IsIoAddress <= Address(7);

    -- Synchronous RAM write, gated so an IO-range store never also writes
    -- RAM at the aliased low-7-bits index (e.g. store to 128 must not
    -- silently write RAM(0)).
    RamWritePort: process (Clock)
    begin
        if rising_edge(Clock) then
            if MemoryWriteEnable = '1' and IsIoAddress = '0' then
                Ram(to_integer(unsigned(Address(6 downto 0)))) <= WriteData;
            end if;
        end if;
    end process;

    -- Asynchronous RAM read.
    ReadData <= Ram(to_integer(unsigned(Address(6 downto 0))));

    -- Unregistered pass-through; valid only while IoEnable = '1'.
    IoAddress <= Address;
    IoData    <= WriteData;
    IoEnable  <= '1' when (MemoryWriteEnable = '1' and IsIoAddress = '1') else '0';

end Behavioral;
