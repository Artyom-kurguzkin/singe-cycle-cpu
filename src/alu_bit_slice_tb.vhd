library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity AluBitSlice_tb is
end AluBitSlice_tb;

architecture Behavioral of AluBitSlice_tb is

    component ALUBitSlice is
        Port (
            Opcode   : in  STD_LOGIC_VECTOR(2 downto 0);
            InputA   : in  STD_LOGIC;
            InputB   : in  STD_LOGIC;
            CarryIn  : in  STD_LOGIC;
            Output   : out STD_LOGIC;
            CarryOut : out STD_LOGIC
        );
    end component;

    signal Opcode   : STD_LOGIC_VECTOR(2 downto 0) := "000";
    signal InputA   : STD_LOGIC := '0';
    signal InputB   : STD_LOGIC := '0';
    signal CarryIn  : STD_LOGIC := '0';
    signal Output   : STD_LOGIC;
    signal CarryOut : STD_LOGIC;

    procedure apply(
        signal op  : out STD_LOGIC_VECTOR(2 downto 0);
        signal a   : out STD_LOGIC;
        signal b   : out STD_LOGIC;
        signal cin : out STD_LOGIC;
        op_val  : in STD_LOGIC_VECTOR(2 downto 0);
        a_val   : in STD_LOGIC;
        b_val   : in STD_LOGIC;
        cin_val : in STD_LOGIC
    ) is
    begin
        op  <= op_val;
        a   <= a_val;
        b   <= b_val;
        cin <= cin_val;
        wait for 20 ns;
    end procedure;

begin

    uut: ALUBitSlice
        port map (
            Opcode   => Opcode,
            InputA   => InputA,
            InputB   => InputB,
            CarryIn  => CarryIn,
            Output   => Output,
            CarryOut => CarryOut
        );

    stimulus: process
    begin

        -- ---- Opcode 000: Addition (A + B + Cin) ----
        -- 0+0+0 = 0, carry 0
        apply(Opcode, InputA, InputB, CarryIn, "000", '0', '0', '0');
        assert Output = '0' and CarryOut = '0' report "ADD 0+0+0 FAILED" severity failure;

        -- 1+0+0 = 1, carry 0
        apply(Opcode, InputA, InputB, CarryIn, "000", '1', '0', '0');
        assert Output = '1' and CarryOut = '0' report "ADD 1+0+0 FAILED" severity failure;

        -- 1+1+0 = 0, carry 1
        apply(Opcode, InputA, InputB, CarryIn, "000", '1', '1', '0');
        assert Output = '0' and CarryOut = '1' report "ADD 1+1+0 FAILED" severity failure;

        -- 1+1+1 = 1, carry 1
        apply(Opcode, InputA, InputB, CarryIn, "000", '1', '1', '1');
        assert Output = '1' and CarryOut = '1' report "ADD 1+1+1 FAILED" severity failure;

        -- ---- Opcode 001: Subtraction (A - B via A + NOT(B) + Cin) ----
        -- 1-0: A=1, B=0 -> A+NOT(B)+Cin = 1+1+0 = 0 carry 1
        apply(Opcode, InputA, InputB, CarryIn, "001", '1', '0', '0');
        assert Output = '0' and CarryOut = '1' report "SUB 1-0 FAILED" severity failure;

        -- 1-1: A=1, B=1 -> 1+0+0 = 1 carry 0
        apply(Opcode, InputA, InputB, CarryIn, "001", '1', '1', '0');
        assert Output = '1' and CarryOut = '0' report "SUB 1-1 FAILED" severity failure;

        -- ---- Opcode 010: AND ----
        apply(Opcode, InputA, InputB, CarryIn, "010", '0', '0', '0');
        assert Output = '0' report "AND 0,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "010", '1', '0', '0');
        assert Output = '0' report "AND 1,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "010", '1', '1', '0');
        assert Output = '1' report "AND 1,1 FAILED" severity failure;

        -- ---- Opcode 011: OR ----
        apply(Opcode, InputA, InputB, CarryIn, "011", '0', '0', '0');
        assert Output = '0' report "OR 0,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "011", '1', '0', '0');
        assert Output = '1' report "OR 1,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "011", '0', '1', '0');
        assert Output = '1' report "OR 0,1 FAILED" severity failure;

        -- ---- Opcode 100: XOR ----
        apply(Opcode, InputA, InputB, CarryIn, "100", '0', '0', '0');
        assert Output = '0' report "XOR 0,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "100", '1', '0', '0');
        assert Output = '1' report "XOR 1,0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "100", '1', '1', '0');
        assert Output = '0' report "XOR 1,1 FAILED" severity failure;

        -- ---- Opcode 101: NOT A ----
        apply(Opcode, InputA, InputB, CarryIn, "101", '0', '0', '0');
        assert Output = '1' report "NOT 0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "101", '1', '0', '0');
        assert Output = '0' report "NOT 1 FAILED" severity failure;

        -- ---- Opcode 110: Left Bit Shift passthrough ----
        -- Output = InputA, CarryOut = InputB (bit shifted out)
        apply(Opcode, InputA, InputB, CarryIn, "110", '1', '0', '0');
        assert Output = '1' and CarryOut = '0' report "LBS A=1,B=0 FAILED" severity failure;

        apply(Opcode, InputA, InputB, CarryIn, "110", '0', '1', '0');
        assert Output = '0' and CarryOut = '1' report "LBS A=0,B=1 FAILED" severity failure;

        -- ---- Opcode 111: Increment (A + 1) ----
        -- inc computes A + CarryIn, so the caller must seed CarryIn='1' to get +1
        -- (this is what alu32.vhd's carry seeding does for real usage)
        -- 0+1 = 1, carry 0
        apply(Opcode, InputA, InputB, CarryIn, "111", '0', '0', '1');
        assert Output = '1' and CarryOut = '0' report "INC 0 FAILED" severity failure;

        -- 1+1 = 0, carry 1
        apply(Opcode, InputA, InputB, CarryIn, "111", '1', '0', '1');
        assert Output = '0' and CarryOut = '1' report "INC 1 FAILED" severity failure;

        report "All tests passed." severity note;
        wait;
    end process;

end Behavioral;
