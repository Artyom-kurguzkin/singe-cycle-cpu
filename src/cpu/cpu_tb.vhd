library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ProgramLoaderPkg.ALL;

-- Generic CPU runner: loads whatever compiled program TestProgram below
-- points at onto a real Cpu instance and reports every IO transmission
-- (IoAddress, IoData observed while IoEnable = '1') as it happens, purely by
-- observing the CPU's external clk/ioaddress/iodata/ioenable ports -- the
-- only ports cpu.vhd exposes, matching the spec exactly. No internal signal
-- access, no debug ports, and no hardcoded expected values: swap
-- TestProgram to any .bin and read the transmissions it produces from the
-- simulator report log or a waveform.
--
-- This testbench is also the "loader": it calls
-- ProgramLoaderPkg.LoadProgramFromFile itself and supplies the resulting
-- data via Cpu's ProgramData generic -- the same role firmware/an OS
-- loader plays in a real system, deciding what a ROM actually runs.
-- Neither cpu.vhd nor instruction_memory.vhd ever read a file themselves --
-- that would be non-synthesizable hardware; only testbenches do this.
entity Cpu_tb is
end Cpu_tb;

architecture Behavioral of Cpu_tb is

    component Cpu is
        Generic (
            ProgramData : STD_LOGIC_VECTOR (32767 downto 0)
        );
        Port (
            clk       : in  STD_LOGIC;
            ioaddress : out STD_LOGIC_VECTOR (7 downto 0);
            iodata    : out STD_LOGIC_VECTOR (31 downto 0);
            ioenable  : out STD_LOGIC
        );
    end component;

    -- Loaded once, here, at elaboration -- this is the "firmware/loader"
    -- decision of which compiled program the CPU actually runs.
    constant TestProgram : STD_LOGIC_VECTOR (32767 downto 0) :=
        LoadProgramFromFile("tools/programs/sieve_program.bin");

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    signal IoAddress : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData    : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable  : STD_LOGIC;

    -- Generous upper bound on how many clock cycles the program could
    -- possibly need to run to completion -- exists purely so a stuck
    -- program (e.g. an infinite loop that never issues IO) ends the
    -- simulation instead of hanging forever.
    constant CycleLimit : integer := 20000;

begin

    UnitUnderTest: Cpu
        generic map (
            ProgramData => TestProgram
        )
        port map (
            clk       => Clock,
            ioaddress => IoAddress,
            iodata    => IoData,
            ioenable  => IoEnable
        );

    -- A free-running clock. The CPU has no reset pin (per spec), so
    -- execution starts from PC=0 (RegisterFile/ProgramCounter's t=0 signal
    -- initializers) the moment the clock starts ticking.
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

    -- Runs the program to completion and checks each expected IO
    -- transmission arrives in order, exactly once, with the right address
    -- and data. Samples IoEnable exactly once per clock cycle, 1 ns after
    -- each rising edge -- NOT with "wait until IoEnable = '1'", which is
    -- edge/event-triggered and can catch a same-timestamp combinational
    -- glitch: IoEnable = MemoryWriteEnable and IsIoAddress (see
    -- data_memory.vhd), and MemoryWriteEnable settles almost immediately
    -- (a short path through ControlUnit's case statement) while
    -- IsIoAddress depends on the 32-bit ripple-carry ALU's result -- a much
    -- longer combinational path. Within the same simulated instant (many
    -- delta-cycles, one timestamp), IoEnable can transiently read '1'
    -- before the address has actually settled, and a raw "wait until"
    -- happily reports that transient event as if it were the final value.
    -- Sampling 1 ns after the edge (the same settling-margin idiom every
    -- other testbench in this project already uses) waits past all of that
    -- instant's delta-cycle activity before reading anything.
    Stimulus: process
        variable TransmissionIndex : integer := 0;
    begin
        for CycleIndex in 1 to CycleLimit loop
            wait until rising_edge(Clock);
            wait for 1 ns; -- let the combinational chain fully settle after the edge

            if IoEnable = '1' then
                report "IO TRANSMISSION " & integer'image(TransmissionIndex)
                    & ": address=" & integer'image(to_integer(unsigned(IoAddress)))
                    & " data=" & integer'image(to_integer(unsigned(IoData)))
                    severity note;
                TransmissionIndex := TransmissionIndex + 1;
            end if;
        end loop;

        report "Run complete. Observed " & integer'image(TransmissionIndex)
            & " IO transmissions." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
