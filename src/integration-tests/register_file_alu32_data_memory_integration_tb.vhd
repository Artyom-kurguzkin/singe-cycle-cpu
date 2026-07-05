library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Integration testbench: wires real RegisterFile, Alu32, and DataMemory
-- instances together (no mocking of any of them) and drives them through
-- the actual shape of `store`/`load` instructions -- computing an address
-- via the ALU (rs + immediate, ALU op forced to add per
-- docs/cpu-implementation-plan.md section 1: "For I-type memory ops (load/
-- store address calc), force ALU op to add"), then exercising DataMemory
-- with that computed address, then writing a loaded value back into the
-- register file. This is the three-module chain the real CPU's memory
-- instructions will run through once cpu.vhd exists; testing it now means
-- any seam bug (wrong operand feeding the address adder, wrong width
-- truncation from the ALU's 32-bit result down to DataMemory's 8-bit
-- address, etc.) gets caught here instead of inside the full CPU.
--
-- Modelled sequence (register/address numbers arbitrary, chosen to avoid
-- collisions):
--   r1 <= 20                                  (seed: base address register)
--   r2 <= 0xCAFEBABE                          (seed: data to store)
--   mem(r1 + 5) <= r2                         (mimics "store r2 r1 5")
--   r3 <= mem(r1 + 5)                         (mimics "load r3 r1 5")
--   assert r3 = 0xCAFEBABE                    (proves the full round trip)
--   mem(r1 + 110) <= r2                       (mimics "store r2 r1 110",
--                                               address 130 falls in the
--                                               IO half -- 20 + 110 = 130)
--   assert IoEnable pulsed with the right IoAddress/IoData, and that RAM at
--   the aliased index (130 - 128 = 2) was NOT written
entity RegisterFileAlu32DataMemoryIntegrationTb is
end RegisterFileAlu32DataMemoryIntegrationTb;

architecture Behavioral of RegisterFileAlu32DataMemoryIntegrationTb is

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

    component Alu32 is
        Port (
            OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
            OperandB : in  STD_LOGIC_VECTOR (31 downto 0);
            OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);
            Result   : out STD_LOGIC_VECTOR (31 downto 0);
            ZeroFlag : out STD_LOGIC
        );
    end component;

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

    signal Clock     : STD_LOGIC := '0';
    signal StopClock : BOOLEAN := false;

    -- RegisterFile signals.
    signal ReadRegisterAddress1 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal ReadRegisterAddress2 : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RegisterReadData1    : STD_LOGIC_VECTOR (31 downto 0);
    signal RegisterReadData2    : STD_LOGIC_VECTOR (31 downto 0);
    signal WriteRegisterAddress : STD_LOGIC_VECTOR (3 downto 0) := (others => '0');
    signal RegisterWriteEnable  : STD_LOGIC := '0';

    -- What gets written back into the register file -- either a seed
    -- constant or DataMemory's ReadData for the `load`-shaped step. A real
    -- CPU would pick this with a MemToReg mux; driven directly here since
    -- there is no control unit yet to generate that mux's select signal
    -- (same approach already used in register_file_alu32_integration_tb.vhd).
    signal RegisterWriteDataMux : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');

    -- Alu32 signals. OperandA is always RegisterReadData1 (rs); OperandB is
    -- the immediate for address calculation, driven directly by the
    -- stimulus process below (standing in for the sign-extended immediate
    -- field a real instruction decoder would produce).
    signal AddressImmediate : STD_LOGIC_VECTOR (31 downto 0) := (others => '0');
    signal AluResult        : STD_LOGIC_VECTOR (31 downto 0);

    -- DataMemory signals. Address is truncated from the ALU's 32-bit
    -- result down to DataMemory's 8-bit address bus -- exactly the
    -- truncation the real CPU's datapath will need between the ALU and the
    -- data memory, since addresses only span 0-255 but the ALU/registers
    -- are all 32 bits wide.
    signal MemoryAddress         : STD_LOGIC_VECTOR (7 downto 0);
    signal MemoryWriteEnable     : STD_LOGIC := '0';
    signal MemoryReadData        : STD_LOGIC_VECTOR (31 downto 0);
    signal IoAddress             : STD_LOGIC_VECTOR (7 downto 0);
    signal IoData                : STD_LOGIC_VECTOR (31 downto 0);
    signal IoEnable               : STD_LOGIC;

begin

    RegisterFileUnderTest: RegisterFile
        port map (
            Clock                => Clock,
            ReadRegisterAddress1 => ReadRegisterAddress1,
            ReadRegisterAddress2 => ReadRegisterAddress2,
            ReadData1            => RegisterReadData1,
            ReadData2            => RegisterReadData2,
            WriteRegisterAddress => WriteRegisterAddress,
            WriteData            => RegisterWriteDataMux,
            RegisterWriteEnable  => RegisterWriteEnable
        );

    -- OperandA = rs (RegisterReadData1); OperandB = the immediate. OpCode
    -- is hardwired to "000" (add) the whole time, matching how the real
    -- control unit will force ALUOp to add specifically for load/store
    -- address calculation (section 1).
    Alu32UnderTest: Alu32
        port map (
            OperandA => RegisterReadData1,
            OperandB => AddressImmediate,
            OpCode   => "000",
            Result   => AluResult,
            ZeroFlag => open
        );

    MemoryAddress <= AluResult(7 downto 0);

    -- WriteData is always rt (RegisterReadData2) -- correct for the
    -- `store`-shaped steps below; unused (but harmless) during the
    -- `load`-shaped step, which drives MemoryWriteEnable = '0' instead.
    DataMemoryUnderTest: DataMemory
        port map (
            Clock             => Clock,
            Address           => MemoryAddress,
            WriteData         => RegisterReadData2,
            MemoryWriteEnable => MemoryWriteEnable,
            ReadData          => MemoryReadData,
            IoAddress         => IoAddress,
            IoData            => IoData,
            IoEnable          => IoEnable
        );

    -- A free-running clock, needed because both RegisterFile's and
    -- DataMemory's write ports are synchronous.
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
        -- ---- "instruction" 1: r1 <= 20 (seed base address register) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(1, 4));
        RegisterWriteDataMux  <= std_logic_vector(to_unsigned(20, 32));
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);

        -- ---- "instruction" 2: r2 <= 0xCAFEBABE (seed data to store) ----
        WriteRegisterAddress <= std_logic_vector(to_unsigned(2, 4));
        RegisterWriteDataMux  <= x"CAFEBABE";
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- ---- "instruction" 3: mem(r1 + 5) <= r2 (mimics "store r2 r1 5") ----
        -- Point rs at r1, rt at r2 -- RegisterReadData1 feeds the ALU's
        -- OperandA and RegisterReadData2 feeds DataMemory's WriteData
        -- directly via the port maps above.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(1, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(2, 4));
        AddressImmediate      <= std_logic_vector(to_unsigned(5, 32));
        MemoryWriteEnable     <= '1';
        wait for 1 ns; -- let the async reads + combinational ALU settle
        assert unsigned(AluResult) = 25
            report "INTEGRATION ADDRESS CALC (r1+5) PRODUCED WRONG RESULT" severity failure;
        wait until rising_edge(Clock);
        MemoryWriteEnable <= '0';

        -- ---- "instruction" 4: r3 <= mem(r1 + 5) (mimics "load r3 r1 5") ----
        -- Same address calculation as the store above (rs=r1, immediate=5),
        -- so this reads back exactly the word instruction 3 wrote.
        AddressImmediate <= std_logic_vector(to_unsigned(5, 32));
        wait for 1 ns;
        assert MemoryReadData = x"CAFEBABE"
            report "INTEGRATION LOAD READ BACK WRONG DATA" severity failure;

        WriteRegisterAddress <= std_logic_vector(to_unsigned(3, 4));
        RegisterWriteDataMux  <= MemoryReadData;
        RegisterWriteEnable   <= '1';
        wait until rising_edge(Clock);
        RegisterWriteEnable <= '0';

        -- Confirm the full round trip: read r3 back out through the
        -- register file's own read port, proving the loaded value actually
        -- survived being latched into the register file, not just that
        -- DataMemory's combinational output happened to be correct in
        -- isolation.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(3, 4));
        wait for 1 ns;
        assert RegisterReadData1 = x"CAFEBABE"
            report "INTEGRATION STORE-THEN-LOAD ROUND TRIP FAILED" severity failure;

        -- ---- "instruction" 5: mem(r1 + 110) <= r2 ----
        -- ---- (mimics "store r2 r1 110", address 130 falls in the IO half) ----
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(1, 4));
        ReadRegisterAddress2 <= std_logic_vector(to_unsigned(2, 4));
        AddressImmediate      <= std_logic_vector(to_unsigned(110, 32));
        MemoryWriteEnable     <= '1';
        wait for 1 ns;
        assert unsigned(AluResult) = 130
            report "INTEGRATION ADDRESS CALC (r1+110) PRODUCED WRONG RESULT" severity failure;
        assert IoEnable = '1'
            and IoAddress = std_logic_vector(to_unsigned(130, 8))
            and IoData = x"CAFEBABE"
            report "INTEGRATION IO-RANGE STORE DID NOT RAISE IoEnable CORRECTLY" severity failure;
        wait until rising_edge(Clock);
        MemoryWriteEnable <= '0';

        -- The IO-range store above must not have corrupted RAM at the
        -- aliased index (130 - 128 = 2): a genuine RAM read of address 2
        -- must still read back zero. r0 was never written by this
        -- testbench, so it still holds its initial value of zero -- using
        -- it as rs here gives AluResult = 0 + 2 = 2 without needing signed
        -- immediate arithmetic just to reach address 2 from r1's base of 20.
        ReadRegisterAddress1 <= std_logic_vector(to_unsigned(0, 4));
        AddressImmediate      <= std_logic_vector(to_unsigned(2, 32));
        MemoryWriteEnable     <= '0';
        wait for 1 ns;
        assert unsigned(MemoryReadData) = 0
            report "INTEGRATION IO-RANGE STORE INCORRECTLY WROTE THROUGH TO ALIASED RAM ADDRESS" severity failure;

        report "All tests passed." severity note;
        StopClock <= true;
        wait;
    end process;

end Behavioral;
