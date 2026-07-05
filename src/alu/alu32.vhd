library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Alu32 is the full 32-bit ALU used by the CPU datapath. It is built
-- structurally out of 32 copies of ALUBitSlice (see alu_bit_slice.vhd) --
-- one per bit position -- chained together so the carry produced by bit i
-- feeds into bit i+1, exactly like a textbook ripple-carry adder. This
-- entity itself contains no per-operation logic (no "if opcode = add then
-- ..."); all of that lives in ALUBitSlice. This file's only job is wiring:
-- fan the shared operands/opcode out to all 32 slices, thread the carry
-- chain through them, and derive the flags the rest of the CPU needs.
entity Alu32 is
    Port (
        -- The two 32-bit operands. For R-type instructions these are the
        -- rs/rt register values; for load/store address calculation
        -- (opcode forced to add) OperandA is rs and OperandB is the
        -- sign-extended immediate.
        OperandA : in  STD_LOGIC_VECTOR (31 downto 0);
        OperandB : in  STD_LOGIC_VECTOR (31 downto 0);

        -- Selects which operation all 32 slices perform this cycle. Values
        -- match the R-type funct field exactly (see docs/cpu-implementation
        -- -plan.md section 1), so the control unit can pass funct straight
        -- through for R-type instructions with no translation logic.
        OpCode   : in  STD_LOGIC_VECTOR (2 downto 0);

        -- The 32-bit result of the selected operation.
        Result   : out STD_LOGIC_VECTOR (31 downto 0);

        -- '1' whenever Result is all zero bits. This is the only ALU flag
        -- the CPU needs: beq/bne implement "rs == rt" by computing rs - rt
        -- (OpCode "001") and checking ZeroFlag -- a subtraction that
        -- produces zero means the two operands were equal. No overflow
        -- flag is exposed because nothing in this CPU's control logic ever
        -- needs one.
        ZeroFlag : out STD_LOGIC
    );
end Alu32;

architecture Structural of Alu32 is

    -- Declares the 1-bit ALU building block so it can be instantiated 32
    -- times below. Port names here must match ALUBitSlice's real entity
    -- ports exactly (Opcode/InputA/InputB/CarryIn/Output/CarryOut) -- this
    -- is a fixed interface we wire to, not a name we get to choose.
    component ALUBitSlice is
        Port (
            Opcode   : in  STD_LOGIC_VECTOR (2 downto 0);
            InputA   : in  STD_LOGIC;
            InputB   : in  STD_LOGIC;
            CarryIn  : in  STD_LOGIC;
            Output   : out STD_LOGIC;
            CarryOut : out STD_LOGIC
        );
    end component;

    -- One extra bit versus the operand width (33 bits, indices 0 to 32):
    -- CarryChain(i) is the carry *into* bit slice i, and CarryChain(i+1) is
    -- the carry *out of* bit slice i (produced by that same slice and fed
    -- into the next one up). CarryChain(0) is the chain's initial seed
    -- (set below); CarryChain(32) would be the carry out of the whole
    -- 32-bit operation, which nothing currently reads (no overflow flag is
    -- exposed -- see ZeroFlag's comment above) but has to exist as a signal
    -- since bit 31's ALUBitSlice instance still needs somewhere to drive
    -- its CarryOut port.
    signal CarryChain          : STD_LOGIC_VECTOR (32 downto 0);

    -- Holds the 32 Output bits coming back from the bit slices before they
    -- are both exposed on the Result port and fed into the ZeroFlag
    -- comparison below. (A signal is needed here, rather than reading back
    -- the Result output port directly, because VHDL doesn't allow reading
    -- the value of an "out" port from within the same entity.)
    signal ResultInternal      : STD_LOGIC_VECTOR (31 downto 0);

    -- A single ALUBitSlice cannot shift itself (its "110" case only passes
    -- InputA straight through -- see alu_bit_slice.vhd), so a real
    -- left-shift-by-1 has to come from feeding bit i's InputA with
    -- OperandA(i - 1) instead of OperandA(i). OperandAShiftedLeft
    -- precomputes that shifted view of OperandA: concatenating
    -- OperandA(30 downto 0) (i.e. OperandA with its top bit dropped) with a
    -- new '0' at the bottom shifts every bit up by one position and fills
    -- in a zero at bit 0, discarding the original bit 31 -- exactly what a
    -- logical left shift by one does.
    signal OperandAShiftedLeft : STD_LOGIC_VECTOR (31 downto 0);

    -- The operand actually fed into each bit slice's InputA: the shifted
    -- view when the opcode is lbs, otherwise the ordinary OperandA
    -- unchanged. Computing this mux once here (rather than inside the
    -- generate loop) keeps the per-bit wiring below simple.
    signal EffectiveOperandA   : STD_LOGIC_VECTOR (31 downto 0);

begin
    -- Seed the very first carry-in of the whole chain.
    --   * sub (OpCode "001") computes A + (NOT B) + CarryIn inside each
    --     slice, which only equals two's-complement subtraction (A - B)
    --     if the chain starts with CarryIn = '1' (the "+1" of "invert and
    --     add one").
    --   * inc (OpCode "111") computes A + CarryIn inside each slice, which
    --     only equals "A + 1" if the chain starts with CarryIn = '1'.
    --   * every other opcode wants an unmodified starting carry of '0'
    --     (plain addition should not add an extra 1; logic ops and the
    --     shift op ignore CarryIn entirely).
    CarryChain(0) <= '1' when (OpCode = "001" or OpCode = "111") else '0';

    -- Precompute "OperandA shifted left by one, zero-filled at bit 0" so
    -- the lbs opcode has something real to select down below.
    OperandAShiftedLeft <= OperandA(30 downto 0) & '0';

    -- Feed the shifted view into the bit slices only when the instruction
    -- being executed is actually lbs; every other opcode sees the operand
    -- completely unchanged, so this mux has zero effect on add/sub/logic/
    -- inc correctness.
    EffectiveOperandA   <= OperandAShiftedLeft when OpCode = "110" else OperandA;

    -- The ripple-carry chain itself: one ALUBitSlice per bit position,
    -- 0 (least significant) through 31 (most significant). "generate" is
    -- VHDL's for-loop for structurally repeating hardware -- this expands
    -- at compile time into 32 separate ALUBitSlice instances, each wired to
    -- a different bit of the operands/result and to neighbouring links in
    -- the carry chain.
    BitSlices: for BitIndex in 0 to 31 generate
        BitSlice: ALUBitSlice
            port map (
                Opcode   => OpCode,
                InputA   => EffectiveOperandA(BitIndex),
                InputB   => OperandB(BitIndex),
                CarryIn  => CarryChain(BitIndex),
                Output   => ResultInternal(BitIndex),
                CarryOut => CarryChain(BitIndex + 1)
            );
    end generate;

    -- Expose the internal result bits on the actual output port.
    Result   <= ResultInternal;

    -- ZeroFlag is '1' exactly when every result bit is '0'. The comparison
    -- "ResultInternal = (ResultInternal'range => '0')" builds an all-zero
    -- vector the same width as ResultInternal (32 bits) and compares it
    -- bit-for-bit, so this keeps working correctly even if the ALU's width
    -- were ever changed.
    ZeroFlag <= '1' when ResultInternal = (ResultInternal'range => '0') else '0';

end Structural;
