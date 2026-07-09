library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Not a correctness test -- a minimal, isolated reproduction of a benign
-- GHDL simulation-startup artifact, kept so it's not mistaken for a real
-- bug when seen in another testbench's output.
--
-- Symptom: any testbench where a memory's address is fed through even one
-- concurrent signal assignment (rather than a directly-initialized signal
-- driven straight by the stimulus process) prints, at simulation start:
--   NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
--
-- Cause: this happens even with every signal explicitly initialized to
-- zero, so nothing is actually undefined. It's a delta-cycle artifact: a
-- signal driven by a concurrent assignment only gets its computed value
-- after that assignment runs at least once, which starts at delta cycle 0
-- of simulation time 0 -- there's an unavoidable one-delta-cycle window
-- before the first evaluation completes. GHDL reports that transient
-- window as a metavalue even though the declared initial value is fine.
-- It self-resolves within the same instant and never persists past @0ms.
--
-- This never contaminates a real assertion because every testbench in
-- this project checks results after a nonzero `wait for ...`, never at
-- time 0. This file demonstrates that: the warning fires, but the value
-- read back after simulated time has elapsed is still correct.
entity MetavalueStartupArtifactDemo_tb is
end MetavalueStartupArtifactDemo_tb;

architecture Behavioral of MetavalueStartupArtifactDemo_tb is

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

    -- Deliberately not driven directly -- derived via one concurrent
    -- assignment below, the minimum needed to reproduce the artifact.
    signal AddressSource     : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal MemoryAddress     : STD_LOGIC_VECTOR (7 downto 0);

    signal WriteData         : STD_LOGIC_VECTOR (31 downto 0) := x"11223344";
    signal MemoryWriteEnable : STD_LOGIC := '1';
    signal ReadData          : STD_LOGIC_VECTOR (31 downto 0);
    signal IoAddress         : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData            : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable          : STD_LOGIC;

begin

    -- The one hop that reproduces the artifact.
    MemoryAddress <= AddressSource(7 downto 0);

    UnitUnderTest: DataMemory
        port map (
            Clock             => Clock,
            Address           => MemoryAddress,
            WriteData         => WriteData,
            MemoryWriteEnable => MemoryWriteEnable,
            ReadData          => ReadData,
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
        -- Write x"11223344" to address 0. Any metavalue warning fires
        -- during elaboration, before this process runs a single statement.
        wait until rising_edge(Clock);

        -- Real time has elapsed well past @0ms; confirm the value is
        -- correct, proving the startup warning left no lasting effect.
        wait for 1 ns;
        assert ReadData = x"11223344"
            report "VALUE AFTER THE @0ms METAVALUE ARTIFACT WAS INCORRECT -- this would mean the artifact is NOT benign and needs real investigation"
            severity failure;

        report "All tests passed (metavalue warning above, if present, is a documented benign @0ms startup artifact)." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
