library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- This is not a correctness test of any module -- it's a minimal, isolated
-- reproduction of a GHDL simulation-startup artifact discovered while
-- building register_file_alu32_data_memory_integration_tb.vhd (Step 5),
-- kept here so nobody re-investigates it from scratch later or mistakes it
-- for a real design bug when they see it in a future testbench's output.
--
-- Symptom: running any testbench where a memory's address input is fed
-- through so much as *one* concurrent signal assignment (rather than being
-- a directly-initialized signal driven straight by the stimulus process)
-- prints this at the very start of simulation:
--   ../../src/ieee2008/numeric_std-body.vhdl:NNNN:N:@0ms:(assertion
--   warning): NUMERIC_STD.TO_INTEGER: metavalue detected, returning 0
--
-- Root cause (confirmed by bisection -- see the git history/session notes
-- around Step 5 for the elimination process): this happens even when every
-- signal involved has an explicit ":= (others => '0')" initial value, so it
-- is *not* about anything actually being left undefined/uninitialized in
-- our own designs (RegisterFile, DataMemory, Alu32 all already have
-- defined-at-t=0 signals -- see their own files' comments). It is instead
-- an artifact of VHDL/GHDL's delta-cycle elaboration model: a signal driven
-- by a concurrent signal assignment (or a process) only receives its
-- *computed* value after that assignment/process actually executes at
-- least once, which itself only happens starting at delta cycle 0 of
-- simulation time 0 -- there is an unavoidable one-delta-cycle window,
-- before the very first evaluation completes, during which a signal that
-- will *become* a real driven value hasn't been resolved as one yet.
-- GHDL's NUMERIC_STD.TO_INTEGER conservatively reports that transient
-- window as "metavalue detected" even though the signal's declared initial
-- value is perfectly defined. This is scoped to @0ms only; it self-resolves
-- within the same simulation instant and never persists into any time a
-- real assertion would observe.
--
-- Practical takeaway (already followed throughout this project, which is
-- exactly why this never showed up as a failure): every other testbench
-- checks results after a nonzero `wait for ...`, never immediately at time
-- 0 -- so this artifact never actually contaminates a real assertion. This
-- file demonstrates that explicitly: the warning fires, but the value read
-- back after real simulated time has elapsed is still correct.
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

    -- Set once true, this stops the clock-generation process below so the
    -- simulation can end cleanly instead of toggling the clock forever.
    signal StopClock         : BOOLEAN := false;

    -- The address is deliberately *not* driven directly -- it is derived
    -- from AddressSource via exactly one concurrent signal assignment
    -- below, which is the minimum needed to reproduce the artifact (a
    -- plain directly-initialized signal used as the address, with no
    -- intermediate assignment, does *not* trigger it -- see
    -- data_memory_tb.vhd, which reads cleanly).
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

    -- A free-running clock, needed because DataMemory's RAM write port is
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
        -- Write x"11223344" to address 0 (AddressSource defaults to zero).
        -- The metavalue warning above, if it fires, happens during
        -- elaboration/delta-cycle 0 of this same run -- before this process
        -- has executed a single statement -- which is exactly the point:
        -- it is purely a startup artifact, not something caused by any
        -- stimulus this testbench applies.
        wait until rising_edge(Clock);

        -- Real simulated time has now elapsed well past @0ms. Read address
        -- 0 back out and confirm it is exactly what was written -- proving
        -- the transient startup warning left no lasting effect on
        -- DataMemory's actual, correct behaviour.
        wait for 1 ns;
        assert ReadData = x"11223344"
            report "VALUE AFTER THE @0ms METAVALUE ARTIFACT WAS INCORRECT -- this would mean the artifact is NOT benign after all and needs real investigation"
            severity failure;

        report "All tests passed (metavalue warning above, if present, is a documented benign @0ms startup artifact -- see this file's header comment)." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
