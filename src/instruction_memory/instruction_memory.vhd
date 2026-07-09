library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

-- Single-read-port instruction ROM: 1024 x 32-bit words, async read (a real
-- ROM has no write port, so nothing to clock).
entity InstructionMemory is
    Generic (
        -- No default: the instantiator must supply the assembled program.
        ProgramData : STD_LOGIC_VECTOR (32767 downto 0)
    );
    Port (
        -- 10 bits = 2^10 = 1024 locations; every address is valid.
        Address        : in  STD_LOGIC_VECTOR (9 downto 0);
        InstructionOut : out STD_LOGIC_VECTOR (31 downto 0)
    );
end InstructionMemory;

architecture Behavioral of InstructionMemory is
begin

    -- Async read: slices the 32-bit word at Address out of ProgramData.
    ReadPort: process (Address)
        variable AddressIndex : integer;
    begin
        AddressIndex := to_integer(unsigned(Address));
        InstructionOut <= ProgramData((AddressIndex + 1) * 32 - 1 downto AddressIndex * 32);
    end process;

end Behavioral;
