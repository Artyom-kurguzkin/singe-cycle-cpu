library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- RegisterFile is the CPU's 16-register scratch storage (r0-r15). Per the
-- spec it needs to support two simultaneous reads and one write per cycle:
-- "Dual read port - single write port, 32-bit wide register bank containing
-- 16 registers." A single-cycle instruction like `add rd, rs, rt` needs
-- both rs and rt available in the same cycle it decodes the instruction
-- (hence two read ports, both async/combinational -- no clock delay before
-- the values are usable), while only ever writing back to one destination
-- register per instruction (hence a single, clocked write port). Note this
-- ISA does not hardwire r0 to zero the way real MIPS does -- Appendix 3's
-- assembly program explicitly does `load immediate r0 0` to put a zero into
-- r0 itself, so r0 must behave as an ordinary read/write register here.
entity RegisterFile is
    Port (
        -- Drives the single write port below. Reads are asynchronous and
        -- do not depend on the clock at all -- see the ReadData1/ReadData2
        -- assignments at the bottom of this file.
        Clock                : in  STD_LOGIC;

        -- Selects which two registers to read this cycle -- typically the
        -- instruction's rs and rt fields. 4 bits wide because there are
        -- 16 registers (2^4 = 16).
        ReadRegisterAddress1 : in  STD_LOGIC_VECTOR (3 downto 0);
        ReadRegisterAddress2 : in  STD_LOGIC_VECTOR (3 downto 0);

        -- The two registers' current values, exposed combinationally (see
        -- below) so the rest of the datapath can use them within the same
        -- cycle without waiting for a clock edge.
        ReadData1            : out STD_LOGIC_VECTOR (31 downto 0);
        ReadData2            : out STD_LOGIC_VECTOR (31 downto 0);

        -- Selects which register gets written this cycle -- typically the
        -- instruction's rd field (R-type) or rt field (load/load-immediate).
        WriteRegisterAddress : in  STD_LOGIC_VECTOR (3 downto 0);

        -- The 32-bit value to write into WriteRegisterAddress, captured on
        -- the next rising clock edge if RegisterWriteEnable is asserted.
        WriteData            : in  STD_LOGIC_VECTOR (31 downto 0);

        -- Write enable for the single write port. Driven by the control
        -- unit (e.g. '0' for instructions like store/beq/bne/jump that
        -- never write back to a register).
        RegisterWriteEnable  : in  STD_LOGIC
    );
end RegisterFile;

architecture Behavioral of RegisterFile is

    -- A plain array of 16 32-bit words models the register bank itself.
    -- Indices 0 to 15 correspond directly to register numbers r0 to r15
    -- (matching the 4-bit register-address fields in the instruction
    -- encoding -- see docs/cpu-implementation-plan.md section 1).
    type RegisterArrayType is array (0 to 15) of STD_LOGIC_VECTOR (31 downto 0);

    -- Initialised to all zeros at simulation start (t=0), the same way the
    -- rest of this simulation-only project relies on VHDL signal
    -- initializers instead of an explicit reset pin (there is no reset port
    -- in this CPU's spec).
    signal Registers : RegisterArrayType := (others => (others => '0'));

begin

    -- The single write port: synchronous (clocked), so a register's value
    -- only ever changes on a rising clock edge, and only when
    -- RegisterWriteEnable is asserted that cycle. Using
    -- to_integer(unsigned(...)) converts the 4-bit address vector into a
    -- plain integer 0-15 so it can index into the Registers array.
    WritePort: process (Clock)
    begin
        if rising_edge(Clock) then
            if RegisterWriteEnable = '1' then
                Registers(to_integer(unsigned(WriteRegisterAddress))) <= WriteData;
            end if;
        end if;
    end process;

    -- The two read ports: plain concurrent signal assignments, not
    -- inside any process or clocked in any way, which is what makes them
    -- asynchronous -- ReadData1/ReadData2 update immediately whenever
    -- ReadRegisterAddress1/2 change, with no clock edge required. This is
    -- what lets both operands of an instruction be read out in the same
    -- cycle the instruction is decoded.
    ReadData1 <= Registers(to_integer(unsigned(ReadRegisterAddress1)));
    ReadData2 <= Registers(to_integer(unsigned(ReadRegisterAddress2)));

end Behavioral;
