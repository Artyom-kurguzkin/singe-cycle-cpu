library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.ProgramLoaderPkg.ALL;

-- Generic CPU runner: loads whatever program TestProgram points at onto a
-- real Cpu instance and reports every IO transmission (IoAddress/IoData
-- while IoEnable='1') as it happens, observing only clk/ioaddress/iodata/
-- ioenable -- no internal signal access, no hardcoded expected values.
-- Also acts as the loader: calls LoadProgramFromFile itself and supplies
-- the result via Cpu's ProgramData generic.
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

    constant TestProgram : STD_LOGIC_VECTOR (32767 downto 0) :=
        LoadProgramFromFile("tools/programs/sieve_program.bin");

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    signal IoAddress : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData    : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable  : STD_LOGIC;

    -- Upper bound on cycles so a stuck program ends the sim instead of
    -- hanging forever.
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

    -- No reset pin: execution starts at PC=0 from signal initializers the
    -- moment the clock starts.
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

    -- Samples IoEnable 1 ns after each rising edge rather than "wait until
    -- IoEnable = '1'": IoEnable = MemoryWriteEnable and IsIoAddress, and
    -- IsIoAddress depends on the ALU's much longer combinational path than
    -- MemoryWriteEnable does, so a same-timestamp glitch can transiently
    -- read '1' before the address settles. Waiting 1 ns clears all of that
    -- delta-cycle activity first.
    Stimulus: process
        variable TransmissionIndex : integer := 0;
    begin
        for CycleIndex in 1 to CycleLimit loop
            wait until rising_edge(Clock);
            wait for 1 ns;

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
