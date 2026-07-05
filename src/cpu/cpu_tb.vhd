library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Full-CPU integration test: runs the hand-assembled test program baked
-- into instruction_memory.vhd (source: tools/programs/cpu_test_program.asm,
-- see that file and instruction_memory.vhd's comments for exactly what it
-- does) on a real Cpu instance, and verifies the outcome purely by
-- observing the CPU's external clk/ioaddress/iodata/ioenable ports -- the
-- only ports cpu.vhd exposes, matching the spec exactly. No internal
-- signal access, no debug ports: this is exactly the same verification
-- technique cpu_sieve_tb.vhd (Step 10) will need for the real sieve
-- program, since the spec's own mechanism for observing CPU results is
-- "transmitted from a memory mapped IO port."
--
-- The test program's tail stores ten registers out to IO addresses
-- 128-137, one per store instruction, in a fixed order (see
-- instruction_memory.vhd's comments for the full address-by-address
-- breakdown). This testbench captures every (IoAddress, IoData) pair
-- observed while IoEnable = '1' during the run, then asserts the captured
-- sequence matches expectations for every instruction class the program
-- exercises: R-type add/sub, a store/load round trip, a taken beq, a taken
-- bne, a not-taken bne (proven by what it did NOT skip), and an
-- unconditional jump (proven by what it DID skip).
entity Cpu_tb is
end Cpu_tb;

architecture Behavioral of Cpu_tb is

    component Cpu is
        Port (
            clk       : in  STD_LOGIC;
            ioaddress : out STD_LOGIC_VECTOR (7 downto 0);
            iodata    : out STD_LOGIC_VECTOR (31 downto 0);
            ioenable  : out STD_LOGIC
        );
    end component;

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    signal IoAddress : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData    : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable  : STD_LOGIC;

    -- One captured IO transmission: which address it targeted and what
    -- data it carried. The test program's tail always stores in the same
    -- fixed order, so this testbench can simply expect them in sequence.
    type IoTransmission is record
        Address : integer;
        Data    : integer;
    end record;
    type IoTransmissionArray is array (natural range <>) of IoTransmission;

    -- Expected (address, data) pairs, in the exact order the test
    -- program's tail issues them (instruction_memory.vhd addresses 21-30):
    --   r3=30 (add), r4=20 (sub), r5=20 (load/store round trip),
    --   r6=0 (proves the beq-taken skip), r7=99 (proves the beq landing),
    --   r8=0 (proves the bne-taken skip), r9=222 (proves the bne-taken
    --   landing), r10=333 (proves the bne-NOT-taken fell through),
    --   r12=555 (proves the jump landing), r13=0 (proves the jump skip).
    constant ExpectedTransmissions : IoTransmissionArray := (
        (128, 30),
        (129, 20),
        (130, 20),
        (131, 0),
        (132, 99),
        (133, 0),
        (134, 222),
        (135, 333),
        (136, 555),
        (137, 0)
    );

    -- Generous upper bound on how many clock cycles the program could
    -- possibly need to produce all expected transmissions (it actually
    -- finishes its 32 instructions, including every branch/jump, well
    -- within this) -- exists purely so a real bug that stops transmissions
    -- from ever arriving fails with a clear assertion instead of hanging
    -- the simulation forever.
    constant CycleLimit : integer := 60;

begin

    UnitUnderTest: Cpu
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
                assert TransmissionIndex <= ExpectedTransmissions'high
                    report "MORE IO TRANSMISSIONS OBSERVED THAN EXPECTED" severity failure;
                assert unsigned(IoAddress) = ExpectedTransmissions(TransmissionIndex).Address
                    report "IO TRANSMISSION "
                        & integer'image(TransmissionIndex)
                        & ": WRONG ADDRESS"
                    severity failure;
                assert unsigned(IoData) = ExpectedTransmissions(TransmissionIndex).Data
                    report "IO TRANSMISSION "
                        & integer'image(TransmissionIndex)
                        & ": WRONG DATA"
                    severity failure;
                TransmissionIndex := TransmissionIndex + 1;
                exit when TransmissionIndex > ExpectedTransmissions'high;
            end if;
        end loop;

        assert TransmissionIndex = ExpectedTransmissions'length
            report "DID NOT OBSERVE ALL EXPECTED IO TRANSMISSIONS WITHIN THE CYCLE BUDGET"
            severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
