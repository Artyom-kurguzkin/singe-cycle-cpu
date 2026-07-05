library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Directed testbench for RegisterFile. Covers: every register starts at
-- zero, a write is only captured on a rising clock edge when
-- RegisterWriteEnable is asserted (and ignored otherwise), both read ports
-- can return two *different* registers' values at the same time, and both
-- read ports can also read the *same* register at the same time (a
-- degenerate but legal case -- e.g. an instruction where rs = rt).
entity RegisterFile_tb is
end RegisterFile_tb;

architecture Behavioral of RegisterFile_tb is

    -- Re-declare the unit under test's interface so this testbench can
    -- instantiate it below.
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

    -- Signals that drive/observe the unit under test.
    signal Clock                : STD_LOGIC := '0';
    signal ReadRegisterAddress1 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadRegisterAddress2 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadData1            : STD_LOGIC_VECTOR (31 downto 0);
    signal ReadData2            : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal WriteData            : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal RegisterWriteEnable  : STD_LOGIC := '0';

    -- Set once true, this stops the clock-generation process below so the
    -- simulation can end cleanly instead of toggling the clock forever.
    signal StopClock : BOOLEAN := false;

begin

    -- Instantiate the actual unit under test, wiring it to the signals
    -- above so the stimulus process can drive it and check its outputs.
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

    -- A free-running clock, 10 ns per half-period (20 ns full period),
    -- needed because RegisterFile's write port is synchronous -- without a
    -- clock edge, a write would never actually take effect.
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
        -- (relies on RegisterFile's Registers signal initializer, the same
        -- t=0-initial-value approach used throughout this simulation-only
        -- project in place of an explicit reset pin).
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(9, 4));
        wait for 1 ns; -- let the async read ports settle
        assert unsigned(ReadData1) = 0 and unsigned(ReadData2) = 0
            report "INITIAL ZERO FAILED" severity failure;

        -- ---- A write with RegisterWriteEnable='0' must be ignored ----
        -- Sets up a write to r5 but leaves the enable low; the write must
        -- not be captured on the next rising edge.
        WriteRegisterAddress <= std_logic_vector(to_unsigned(5, 4));
        WriteData            <= x"DEADBEEF";
        RegisterWriteEnable  <= '0';
        wait until rising_edge(Clock);
        wait for 1 ns; -- let the async read ports settle after the edge
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(5, 4));
        wait for 1 ns;
        assert unsigned(ReadData1) = 0
            report "WRITE WITHOUT ENABLE WAS CAPTURED" severity failure;

        -- ---- A write with RegisterWriteEnable='1' is captured on the ----
        -- ---- next rising edge, and reads back correctly afterwards ----
        RegisterWriteEnable <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0'; -- de-assert so no register keeps being overwritten
        wait for 1 ns;
        assert ReadData1 = x"DEADBEEF"
            report "WRITE-THEN-READBACK ON PORT 1 FAILED" severity failure;

        -- ---- Simultaneous dual-read of two *different* registers ----
        -- Write a second, distinct value into r10, then read r5 on port 1
        -- and r10 on port 2 at the same time -- proves the two read ports
        -- are genuinely independent rather than sharing one address.
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

        -- ---- Simultaneous dual-read of the *same* register ----
        -- A degenerate but legal case (e.g. an instruction where rs = rt,
        -- such as beq r2 r2 comparing a register to itself) -- both ports
        -- must return the same value when pointed at the same address.
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
