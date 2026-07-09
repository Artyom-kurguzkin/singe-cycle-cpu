library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- 16-register file (r0-r15): dual async read port + single sync write port.
-- r0 is an ordinary read/write register, not hardwired to zero.
entity RegisterFile is
    Port (
        Clock                : in  STD_LOGIC;

        -- Register numbers to read this cycle (e.g. rs/rt).
        ReadRegisterAddress1 : in  STD_LOGIC_VECTOR (3 downto 0);
        ReadRegisterAddress2 : in  STD_LOGIC_VECTOR (3 downto 0);

        -- Combinational reads; default to zero so t=0 is defined.
        ReadData1            : out STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
        ReadData2            : out STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

        -- Single write port: register number, value, and enable.
        WriteRegisterAddress : in  STD_LOGIC_VECTOR (3 downto 0);
        WriteData            : in  STD_LOGIC_VECTOR (31 downto 0);
        RegisterWriteEnable  : in  STD_LOGIC
    );
end RegisterFile;

architecture Behavioral of RegisterFile is

    type RegisterArrayType is array (0 to 15) of STD_LOGIC_VECTOR (31 downto 0);

    -- Zeroed at t=0 (no reset pin on this CPU).
    signal Registers : RegisterArrayType := (others => (others => '0'));

begin

    -- Synchronous write: latches WriteData into WriteRegisterAddress on the
    -- rising edge, only when RegisterWriteEnable = '1'.
    WritePort: process (Clock)
    begin
        if rising_edge(Clock) then
            if RegisterWriteEnable = '1' then
                Registers(to_integer(unsigned(WriteRegisterAddress))) <= WriteData;
            end if;
        end if;
    end process;

    -- Asynchronous reads: update immediately on address change, no clock.
    ReadData1 <= Registers(to_integer(unsigned(ReadRegisterAddress1)));
    ReadData2 <= Registers(to_integer(unsigned(ReadRegisterAddress2)));

end Behavioral;
