library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for RegisterFile: registers start at zero, a write is
-- captured only on a rising edge with RegisterWriteEnable asserted, both
-- read ports can return different registers at once, and both can read the
-- same register at once (e.g. rs = rt).
entity RegisterFile_tb is
end RegisterFile_tb;

architecture Behavioral of RegisterFile_tb is

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

    signal Clock                : STD_LOGIC := '0';
    signal ReadRegisterAddress1 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadRegisterAddress2 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadData1            : STD_LOGIC_VECTOR (31 downto 0);
    signal ReadData2            : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal WriteData            : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal RegisterWriteEnable  : STD_LOGIC := '0';

    signal StopClock : BOOLEAN := false;

begin

    UnitUnderTest: RegisterFile
        port map (
            Clock                => Clock,
            ReadRegisterAddress1 => ReadRegisterAddress1,
            ReadRegisterAddress2 => ReadRegisterAddress2,
            ReadData1            => ReadData1,
            ReadData2            => ReadData2,
            WriteRegisterAddress => WriteRegisterAddress,
            WriteData            => WriteData,
            RegisterWriteEnable  => RegisterWriteEnable
        );

    -- 20 ns period clock; needed because the write port is synchronous.
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
        -- ---- Every register reads back as zero before any write ----
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(9, 4));
        wait for 1 ns;
        assert unsigned(ReadData1) = 0 and unsigned(ReadData2) = 0
            report "INITIAL ZERO FAILED" severity failure;

        -- ---- A write with RegisterWriteEnable='0' must be ignored ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(5, 4));
        WriteData            <= x"DEADBEEF";
        RegisterWriteEnable  <= '0';
        wait until rising_edge(Clock);
        wait for 1 ns;
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(5, 4));
        wait for 1 ns;
        assert unsigned(ReadData1) = 0
            report "WRITE WITHOUT ENABLE WAS CAPTURED" severity failure;

        -- ---- A write with enable='1' is captured on the next edge ----
        RegisterWriteEnable <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';
        wait for 1 ns;
        assert ReadData1 = x"DEADBEEF"
            report "WRITE-THEN-READBACK ON PORT 1 FAILED" severity failure;

        -- ---- Simultaneous dual-read of two different registers ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(10, 4));
        WriteData            <= x"CAFEF00D";
        RegisterWriteEnable  <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(5, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(10, 4));
        wait for 1 ns;
        assert ReadData1 = x"DEADBEEF" and ReadData2 = x"CAFEF00D"
            report "SIMULTANEOUS DUAL-READ (DIFFERENT REGS) FAILED" severity failure;

        -- ---- Simultaneous dual-read of the same register ----
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(10, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(10, 4));
        wait for 1 ns;
        assert ReadData1 = x"CAFEF00D" and ReadData2 = x"CAFEF00D"
            report "SIMULTANEOUS DUAL-READ (SAME REG) FAILED" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
