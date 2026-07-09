# How This CPU Was Built: A Detailed Development Report

This document explains, from scratch and in plain language, how this project
went from an empty repository to a working 32-bit single-cycle CPU that runs
a real assembly program (a Sieve of Eratosthenes that finds prime numbers up
to 127). It's written from the git history (13 commits) plus the actual
source code, and it assumes you don't already know how this specific project
works — jargon is explained as it comes up.

If you just want the short version: this is a school assignment (ENGR3701)
to build a simple CPU in VHDL (a hardware description language — you write
"code" that describes circuits, not a program that runs on a CPU), simulate
it with a free tool called GHDL, and prove it works by running a hand-written
assembly program on it. The CPU has no display, no keyboard, nothing physical
— its only way of "talking to the outside world" is a memory-mapped IO bus,
and the only program it needs to run is the prime sieve.

---

## 1. The big picture: what is a "single-cycle CPU" and why does this project look the way it does

A CPU's job, at the most basic level, is a loop:

1. **Fetch** — read the next instruction from memory.
2. **Decode** — figure out what that instruction means (add two numbers?
   store something? jump somewhere?).
3. **Execute** — do the arithmetic/logic.
4. **Memory** — read or write RAM if the instruction needs to.
5. **Write-back** — save any result into a register.

A **single-cycle** CPU does all five of those steps in one single clock
tick, for every instruction, no matter how simple or complex that
instruction is. This is the simplest possible CPU design (as opposed to
"multi-cycle" or "pipelined" designs used in real processors, which split
those steps across multiple clock ticks to run faster) and it's what this
assignment specifically asks for.

Because every instruction must finish in one clock cycle, all of the CPU's
internal logic has to be **combinational** (i.e., plain wires and logic
gates that settle to their answer near-instantly) rather than clocked in
stages. The only things in this whole design that actually have "memory"
(state that persists between clock cycles) are:
- the **Program Counter** (which instruction we're on),
- the **Register File** (16 general-purpose scratch registers),
- and **RAM** (128 words of data memory).

Everything else — the ALU, the instruction decoder, the next-PC logic — is
just wires and logic that gets recomputed fresh every single clock cycle.

### Harvard architecture (two separate memories)

Unlike your typical laptop/phone CPU (or even textbook MIPS), which stores
both instructions and data in one shared memory, this spec asks for **two
separate memories**: one for instructions (`InstructionMemory`, a read-only
"ROM" of 1024 instructions) and one for data (`DataMemory`, 128 words of
read/write RAM). This is called a **Harvard architecture**, and it exists
here mostly because the spec says so — it also conveniently means the
instruction-fetch logic and the data load/store logic never have to fight
over the same memory port.

### Memory-mapped IO — how this CPU "talks" to anything

This CPU has no screen, no serial port — nothing. But it needs some way to
report the primes it finds. The spec's answer is a classic hardware trick
called **memory-mapped IO**: `DataMemory`'s address space is 256 values (8
bits), and it's split in half by nothing more than looking at the top bit of
the address:
- addresses 0–127 (top bit = 0) → real RAM,
- addresses 128–255 (top bit = 1) → "the outside world."

When a `store` instruction targets an address ≥ 128, `DataMemory` does *not*
write it into RAM. Instead it raises a signal called `IoEnable` for exactly
that one clock cycle, while `IoAddress`/`IoData` show what was being sent.
The spec doesn't require anything to actually *receive* that data — "the IO
registers themselves do not need to be implemented" — so in this project the
"outside world" listening on that bus is just the testbench, watching those
three wires and printing what it sees. When the sieve program finds a prime,
it does a `store` to one of these IO addresses, and that's the whole
mechanism by which "the CPU outputs primes."

---

## 2. Development philosophy: bottom-up, test every seam

Looking at the 13 commits in order, the project was built **bottom-up**:
build the smallest, most self-contained piece first (a single bit of an
ALU), test it in total isolation, then build the next piece up, test *that*
in isolation, and then — critically — also test that the new piece actually
cooperates correctly with everything built so far, before moving on. This
"test every seam" habit shows up repeatedly as small **integration
testbenches** living in `src/integration-tests/`, separate from each
module's own unit testbench. The reasoning, straight from the project's own
planning doc: *"bugs at the seams are much cheaper to find here"* — i.e., far
cheaper to find a wiring mistake between two modules with a 20-line test
right after building them, than to find the same mistake buried inside the
full CPU running a 30-instruction program weeks later.

The build order was:

```
ALU (bit-slice → 32-bit)
  → Register File            [+ integration test vs ALU]
  → Instruction Memory (ROM) [+ integration test vs ALU, previewing PC logic]
  → Data Memory (RAM + IO)   [+ integration test vs RegisterFile + ALU]
  → Control Unit             [+ integration test vs RegisterFile+ALU+DataMemory]
  → Program Counter Unit     [+ integration test vs ControlUnit+ALU]
  → Cpu (top-level wiring of everything above)
  → Assembler (tools/assemble_sieve.py) + a hand-written test program
  → Program loader mechanism
  → The real Sieve of Eratosthenes program
```

Every module also got its own dedicated folder under `src/` (e.g.
`src/alu/alu32.vhd` + `src/alu/alu32_tb.vhd`), so each module's
implementation lives right next to the test that proves it works.

### A rule adopted early and applied everywhere: assertions must actually fail the build

The very first thing done in this project (Step 1) was sanity-testing the
dev environment against some throwaway example files (`src/example/`, never
used again after this). Doing that surfaced an important lesson: the example
testbench used `assert ... severity error` on its checks. In VHDL/GHDL,
`severity error` **prints a message but does not stop the simulation** — so
a test could fail (print e.g. `INC 0 FAILED`) and the simulation would just
carry on and print `All tests passed.` right after anyway, which is an
outright lie about the result. From that point on, this project enforced one
rule everywhere: **every assertion in every testbench uses `severity
failure`**, which actually halts the simulation immediately and makes the
whole `make sim` command return a failure exit code. This is why, throughout
this codebase, you'll never see `severity error` or `severity warning` on a
correctness check — only `severity failure`. (The one exception is a final
"all done" `report ... severity note`, which is just an informational
message, not a check.)

### A rule for comments: comment heavily, and explain *why*

The project's planning document also set a house style for comments: not
just "what" a piece of code does (identifiers are supposed to already make
that obvious — see the naming convention below) but **why** — why a signal
exists, why a mux is shaped a certain way, why a particular bit width was
chosen. This was a deliberate choice specifically because the assignment's
written report needs to describe the design in detail, so heavily-commented
source code doubles as that documentation. This is why almost every `.vhd`
file in this repo reads like a small essay above each entity/signal, rather
than terse one-liners.

### A rule for naming: no cryptic single-letter names

Also from the planning doc: no `a`, `b`, `s`, `i`, `tmp` — every signal gets
a full descriptive name (`OperandA`, `OperandB`, `Result`, `ZeroFlag`,
`BitIndex`, etc.), C#-style. Well-known acronyms (`ALU`, `PC`, `CPU`, `IO`)
are still fine as-is.

---

## 3. The false start: trying to target real FPGA hardware, then rolling it back

Before any real CPU code was written, the very first attempt (commit
`9544a80`, "attempting to retool for fpga builds") tried to turn the dev
container into a *complete FPGA toolchain*: on top of GHDL (the VHDL
simulator), it pulled in `yosys` (synthesis), `nextpnr-xilinx` (place &
route for Xilinx chips, built from source with `cmake`), `prjxray` (the
open-source Xilinx bitstream database/tools), and a ~600MB device database
(`prjxray-db`) — all aimed at eventually producing a real bitstream to
program onto physical FPGA hardware (a Nexys board, mentioned in one of the
background PDFs).

This was rolled back one commit later (`49cb4cc`, "rolled back to previous
working setup"). The reasoning, recorded afterwards in the planning doc,
is straightforward: **this assignment is simulation-only.** Nothing in the
spec asks for a bitstream or real hardware — it only asks for a working
VHDL simulation (GHDL) that can be shown to run the sieve program correctly.
Dragging in an entire FPGA synthesis/place-and-route toolchain (several
`cmake`-built C++ tools, gigabytes of dependencies, hour-plus Docker build
times) bought nothing for that goal and made the dev environment far more
fragile. The rollback replaced the sprawling `ubuntu:22.04`-based Dockerfile
with a lean `debian:bookworm-slim` image that installs essentially just
`ghdl`, `make`, `git`, `curl`, `sudo` — and that minimal container is what
the entire rest of the project (all 12 later commits) was built and tested
against. This decision is recorded explicitly in the planning doc's "Scope
decisions" section so nobody re-attempts the FPGA route later by mistake.

---

## 4. The build, module by module

### ALU (`src/alu/alu_bit_slice.vhd`, `src/alu/alu32.vhd`)

The ALU (Arithmetic Logic Unit) is the part of the CPU that actually does
math and logic: add, subtract, AND, OR, XOR, NOT, a left-shift, and
increment. It's built the classic textbook way for a course like this: as a
**bit-slice ALU**.

- `ALUBitSlice` is a tiny ALU that only knows how to operate on **one single
  bit** at a time, plus a carry-in/carry-out for arithmetic. It has an
  `Opcode` input selecting which of the 8 operations to perform (the opcode
  values exactly match the ISA's R-type "funct" field — see the instruction
  set section below — so the control unit never needs any translation logic
  for R-type instructions).
- `Alu32` wires up **32 copies** of `ALUBitSlice` side by side (using a VHDL
  `generate` loop, which is like a hardware "for loop" that gets expanded
  into 32 real, separate circuit instances at compile time), threading each
  slice's carry-out into the next slice's carry-in — exactly how you'd chain
  32 one-bit full-adders together to build a 32-bit ripple-carry adder by
  hand.

Two non-obvious design details worth calling out:

- **Subtraction and increment reuse the same adder hardware.** Subtraction
  is computed as `A + (NOT B) + CarryIn` (two's-complement subtraction: `A -
  B == A + (~B) + 1`), and increment is computed as `A + CarryIn` (i.e. `A +
  1`). Both of these only produce the right answer if the *very first*
  carry-in of the whole 32-bit chain is seeded to `'1'` — which `Alu32` does
  with one line: `CarryChain(0) <= '1' when (OpCode = "001" or OpCode =
  "111") else '0';`. Every other opcode gets `'0'` there instead.
- **A single bit-slice literally cannot shift a value**, because shifting
  means moving a bit *from one position to a different position*, and one
  slice only ever sees one bit position. So the left-shift opcode
  (`"110"`) is really two things working together: each `ALUBitSlice`, when
  given that opcode, just passes its input straight through unchanged — and
  `Alu32` is the one that actually performs the shift, by feeding bit `i`'s
  input from `OperandA(i - 1)` instead of `OperandA(i)` whenever the opcode
  is a shift (with a `0` filled in at the very bottom, and the top bit
  simply falling off the end — a logical left shift by exactly 1 bit). This
  distinction — "the bit slice can't shift, only the 32-bit wrapper can" —
  turned out to matter for a real bug (see the bug list below).

`Alu32` exposes exactly one flag, `ZeroFlag` (`'1'` when the 32-bit result
is all zero bits) — no overflow flag, because nothing downstream in this CPU
ever needs one. `ZeroFlag` matters specifically for `beq`/`bne`
(branch-if-equal/not-equal): both are implemented as "subtract the two
registers, then look at whether the result was zero."

### Register File (`src/register_file/register_file.vhd`)

16 general-purpose 32-bit registers (`r0`–`r15`). Per the spec: **two
simultaneous read ports, one write port.** The two reads are asynchronous
(pure combinational logic — they update instantly whenever the requested
register number changes, no clock wait), which is what lets a single-cycle
instruction like `add rd, rs, rt` grab both `rs` and `rt`'s values in the
same instant it decodes the instruction. The one write port is synchronous
(clocked) — a register's value can only actually change on a rising clock
edge, and only if `RegisterWriteEnable` is asserted that cycle.

One detail that trips people up if they've seen real MIPS before: **`r0` is
not hardwired to zero here.** In real MIPS, register 0 always reads as zero
no matter what you write to it. This ISA's spec doesn't say that, and the
example assembly program explicitly does `load immediate r0 0` to *put* a
zero into `r0` itself — so this register file treats `r0` as an entirely
ordinary, freely read/write register.

### Instruction Memory (`src/instruction_memory/instruction_memory.vhd`)

A 1024-word, 32-bit-wide, read-only "ROM." Since it's read-only, there's no
clock involved at all — the output simply reflects whatever the `Address`
input currently points at (asynchronous read), the same way a real ROM chip
has no concept of a write cycle.

The interesting design question here was: **how does a compiled program
actually get into this ROM?** That question, and the four different
approaches tried and rejected before landing on the final one, gets its own
section below (section 5) because it's one of the more instructive parts of
this project's history.

### Data Memory (`src/data_memory/data_memory.vhd`)

128 words of real read/write RAM, plus the address-range decode logic
described in section 1 (top address bit picks RAM vs. the IO bus). The key
correctness detail: **an IO-range store must never also write into RAM.**
Address 200, for example, and address 200 − 128 = 72 alias to the same
7-bit index if you're not careful — so the RAM write is explicitly gated on
`MemoryWriteEnable = '1' and IsIoAddress = '0'`, ensuring a store to the IO
half of the address space physically cannot land in the RAM array as a
side effect.

### Control Unit (`src/control_unit/control_unit.vhd`)

This is the instruction decoder — the part that looks at an instruction's
opcode (and, for R-type instructions, its 3-bit function code) and produces
every control signal the rest of the CPU needs that cycle (which register
to write, which ALU operation to run, whether to write memory, whether to
branch/jump, etc). It does no actual computation itself — just decides how
everything else should be wired together for the current instruction. Two
signals were added here beyond the most basic textbook sketch, both because
of specifics of *this* ISA:

- **`AluOperandAZero`** — `load immediate` needs to compute `0 OP immediate`
  so the immediate can ride the ALU's normal write-back path instead of
  needing a whole separate data path just for itself. Since this ISA's `r0`
  is *not* hardwired to zero (see above), the control unit can't just assume
  "read `r0`, it'll be zero" — it has to force the ALU's first operand to a
  literal zero directly, independent of whatever any given program happens
  to have stored in `r0`.
- **`ImmediateZeroExtend`** — the instruction word's 16-bit immediate field
  means two different things depending on the instruction: `load immediate`
  wants it **zero-extended** (padded with 0s) to 32 bits, while `load`/
  `store` address calculation wants it **sign-extended** (padded with the
  sign bit, so a negative offset stays negative) — standard practice for an
  address offset that might need to go backwards. Since both cases share
  the same "second ALU operand is the immediate" path, something has to
  tell the CPU which kind of extension to apply, and that's this signal.

### Program Counter Unit (`src/pc_unit/pc_unit.vhd`)

Pure combinational "what should the PC become next" logic — sequential
(`PC + 1`), a taken branch (`PC + sign_extend(offset)`), or an absolute
jump, in that priority order. It deliberately holds **no register of its
own** — the actual PC register that remembers this value between clock
edges lives in `cpu.vhd`, the top-level file, mirroring how `Alu32` computes
values but never stores any of its own results either. One subtlety: a
branch is taken when `BranchEnable` is set (this is a `beq`/`bne`) *and*
`ZeroFlag` matches the polarity the specific branch wants (`beq` wants
`ZeroFlag='1'`, `bne` wants `ZeroFlag='0'`) — expressed as `BranchEnable and
(ZeroFlag xnor BranchOnZero)`, using `xnor` specifically because plain `=`
on two 1-bit signals returns a different data type (`BOOLEAN`) that can't be
combined with `and` directly against another 1-bit signal.

### Cpu — the top-level module (`src/cpu/cpu.vhd`)

This is where every module above finally gets wired together into one real
CPU. It owns the two pieces of state that don't belong to any single
sub-module: the actual clocked Program Counter register, and the logic that
slices a freshly-fetched 32-bit instruction word into its individual fields
(opcode, `rs`, `rt`, `rd`, function code, immediate, jump address) according
to the instruction format tables (see the ISA section below). Its external
ports are exactly what the assignment spec mandates and nothing more: `clk`,
`ioaddress`, `iodata`, `ioenable` — no reset pin (the spec doesn't have one;
every piece of state gets its starting value of zero from a VHDL signal
initializer instead, which is fine since this project is simulation-only).

---

## 5. The saga of "how does a compiled program get into the CPU?"

This was one of the more genuinely tricky design questions in the whole
project, and the planning document specifically preserves the full list of
approaches tried and rejected — worth understanding because each rejected
option is a reasonable-looking idea that turns out to be wrong for a subtle
reason.

**The final design:** `InstructionMemory` (and `cpu.vhd`, which just forwards
it through) takes its entire program contents via a VHDL **generic** called
`ProgramData` — a 32,768-bit vector (1024 instructions × 32 bits, all
flattened into one giant bit vector, since VHDL doesn't easily let you pass
an array of a not-yet-shared custom type between separately-compiled files
without a package). A generic is resolved once, at "elaboration" (VHDL's
term for wiring everything together before simulation starts) — never
during the simulation itself. A separate tool, `tools/assemble_sieve.py`
(a small two-pass assembler written in Python — pass 1 finds every label's
address, pass 2 actually encodes each instruction), reads a human-written
`.asm` file and emits **plain machine code**: one file of 1s and 0s, one
instruction per line. Then a small VHDL package, `program_loader_pkg.vhd`,
provides exactly one function — `LoadProgramFromFile` — that reads that
machine-code file and builds the 32,768-bit generic value from it. Only
**testbenches** ever call this function; `cpu.vhd`/`instruction_memory.vhd`
never touch a file, ever.

**Why not the more "obvious" alternatives?** Four were tried/considered and
specifically ruled out, each for a reason worth remembering:

1. **Hardcode the program directly inside `instruction_memory.vhd`.** This
   is literally what the first draft did (Step 4), with 4 placeholder
   instructions written straight into the VHDL source. The problem: every
   time the program changes (and it changed at least twice — a test
   program, then the real sieve), you'd have to hand-edit the hardware
   description file itself. That's exactly the maintenance problem this
   whole mechanism exists to avoid.
2. **Read the program file from *inside* `instruction_memory.vhd` or
   `cpu.vhd` directly.** File I/O (`STD.TEXTIO`, VHDL's equivalent of
   reading a text file) is inherently **non-synthesizable** — there is no
   real-silicon equivalent of "open a file and read lines from it." Even
   though this project never actually needs to synthesize real hardware
   (see the FPGA-rollback story above), putting file-reading logic inside
   what's supposed to be a hardware description is considered bad practice
   here regardless — a real ROM's contents are fixed at fabrication time,
   and a generic (resolved once, before the "chip" even exists) is the
   honest hardware analogy for that, whereas file I/O implies something
   that could change live, which a real ROM never does.
3. **Compile each program into its own VHDL package** (e.g. a
   `sieve_program_pkg.vhd` holding a VHDL constant with the whole program
   baked in). Rejected because an assembler's job is to emit *machine code*,
   not to emit source code in some other programming language — and
   generating a fresh `.vhd` file per program also reopens VHDL's
   package-analysis-ordering problem (any file that `use`s a package must be
   compiled *after* that package), for genuinely no benefit, since the
   binary-file approach sidesteps that problem almost entirely (except for
   the one, permanent, `program_loader_pkg.vhd` file).
4. **A custom shared array type** (e.g. an array of 1024
   `STD_LOGIC_VECTOR(31 downto 0)` words) passed around via its own shared
   package. Rejected because the only reason you'd need a shared package
   here is so every file agrees on the same custom type — and flattening
   everything down to one plain `STD_LOGIC_VECTOR` (which is already a
   built-in, universally-recognized VHDL type) sidesteps that need
   entirely.
5. **A loader as a hardware component** (an entity called `ProgramLoader`,
   instantiated inside `cpu.vhd`, that reads the file and drives
   `InstructionMemory`'s input as a live signal). This one was actually
   built and worked — but it's still fake, non-synthesizable "hardware"
   sitting directly inside the CPU's own structural description, wired
   through a runtime signal, which is exactly the same problem as option 2
   above just wearing a different hat. The final design (a plain function,
   callable only by testbenches, with zero presence inside `cpu.vhd`'s own
   body) has no such problem at all.

The upshot: swapping which program the CPU runs is now a one-line change in
a testbench (which `.bin` file path gets passed to `LoadProgramFromFile`) —
`cpu_tb.vhd` currently points at `tools/programs/sieve_program.bin`, having
earlier pointed at a smaller hand-written `cpu_test_program.bin` used while
building the CPU up module by module.

---

## 6. The instruction set (ISA), briefly

Every instruction is a fixed 32 bits, in one of three formats:

| Format | Layout |
|---|---|
| R (register-register ops) | `opcode(6) \| rs(4) \| rt(4) \| rd(4) \| funct(3) \| unused(11)` |
| I (immediate/memory/branch ops) | `opcode(6) \| rs(4) \| rt(4) \| immediate(16) \| unused(2)` |
| J (jump) | `opcode(6) \| address(10) \| unused(16)` |

| Name | Type | Meaning |
|---|---|---|
| add/sub/and/or/xor/not/lbs/inc | R | ordinary ALU ops between registers (`lbs` = left-shift-by-1) |
| load immediate | I | `rt = zero_extend(immediate)` |
| load | I | `rt = mem[rs + immediate]` |
| store | I | `mem[rs + immediate] = rt` |
| beq / bne | I | branch if `rs == rt` / `rs != rt` |
| jump | J | unconditional absolute jump |

A few resolved ambiguities worth knowing (the spec's own written
description wasn't 100% explicit about these, and they were worked out by
reverse-engineering the example assembly program line by line):

- **The PC counts instructions, not bytes.** Unlike textbook MIPS (which
  counts bytes and needs a ×4 shift for jump/branch targets), this PC
  literally just counts 0, 1, 2, 3... one number per instruction. No
  shifting needed anywhere.
- **R-type register field order is `rs, rt, rd`** — confirmed by finding
  the one line in the example program where all three registers are
  different (`sub r6 r3 r7`) and noting that `rd` *must* be the freshly-used
  register, since it's never read from beforehand.
- **`load` and `store` don't share one "generic" operand order.** In the
  example assembly text, `load`'s operands read as (destination, address,
  offset) while `store`'s read as (address, data, offset) — an asymmetry
  that genuinely matters when hand-transcribing assembly, and which
  actually caused a real bug (see the bug list below).

---

## 7. How the assembler (`tools/assemble_sieve.py`) actually works

An assembler's job is to turn human-readable text like `store r4 r2 0` into
the raw 32-bit binary word the CPU actually fetches and decodes. This one is
a small, plain Python script (no external libraries) that works in the
classic **two passes**:

**Pass 1 — `tokenize_source`: figure out addresses and labels, don't encode
anything yet.** It walks the `.asm` file line by line, stripping `--`
comments and blank lines. A line like `#label1` doesn't produce an
instruction at all — it just records "the *next* real instruction will live
at whatever address we're up to" in a `labels` dictionary, so
`labels["label1"] == 6` means label1 points at instruction address 6. Every
other line is split into a mnemonic and its operands and stored, address
already assigned, for pass 2 to deal with. This has to be a separate pass
from encoding because a branch near the top of the program might jump to a
label defined near the bottom — you can't know that label's address until
you've scanned the whole file once.

**Pass 2 — `encode_instruction`: turn each parsed line into a 32-bit
integer.** This is where the real work happens, and the key design choice
is: **each mnemonic gets its own dedicated branch of if-statements, matching
that specific mnemonic's documented operand order** — the assembler does not
try to be one generic "opcode + operand-list" parser. This is a deliberate
choice, straight from the ISA ambiguity noted earlier (section 6): `load`'s
text operand order is `(destination, address-register, offset)` while
`store`'s is `(address-register, data-register, offset)` — genuinely
different orders for two superficially similar instructions. A single
generic parser would have no way to know which order applies to which
mnemonic; writing a dedicated branch per mnemonic makes that distinction
explicit in the code itself; this is exactly what turned bug 8.8 (a
transcription mistake in the *assembly source*) into something a human
could catch by re-reading the source, rather than a mistake the assembler
could have silently propagated.

Each branch does three things: checks it got the right number of operands
(raising a clear `AssemblyError` naming the offending source line if not),
resolves each operand (a register like `r4` → the integer 4, via
`parse_register`; a plain number via `parse_integer`), and packs the pieces
into a 32-bit integer with plain bit-shifting arithmetic — e.g. R-type
instructions are built with `(0 << 26) | (rs << 22) | (rt << 18) | (rd <<
14) | (funct << 11)`, directly mirroring the bit-layout table from section 6.
Branch/jump targets get special handling since they can be written either as
a raw number or as a `#label` reference:
- `beq`/`bne` operands are a **relative offset** (how far to jump from
  *this* instruction), so a label resolves to `label_address -
  current_address`, then gets range-checked to fit the ISA's signed 10-bit
  branch field (-512 to 511).
- `jump`'s operand is an **absolute address** (where to go, full stop), so a
  label just resolves directly to its own address, range-checked to fit the
  10-bit field (0-1023).

Both of those range checks matter: they turn "silently truncated, wrong
address at runtime" into "the assembler refuses to build the program at
all, with a line number," the same philosophy as `severity failure` for
testbenches (section 2) applied to the assembler instead.

**Output — two files, both plain machine code, never VHDL** (this is
exactly the same "never emit hardware description language from a
compiler" decision covered in section 5): `write_machine_code` produces the
actual `--bits-out` file the CPU testbenches load — one line per
instruction, each line exactly 32 characters of `0`/`1`, nothing else, in
address order. `write_binary_listing` produces the human-friendly
`--binary-out` file — the same instructions, but with each field
(opcode/rs/rt/rd/funct or opcode/address/unused, depending on format) shown
space-separated, plus the original source line as a trailing comment, purely
so a person can visually verify what got encoded (this is what caught bug
8.8 — the operand-order mistake was spotted by eye in exactly this listing
file, compared against hand-computed expected values).

Any address that falls past the end of the actual program, up to the full
1024-word instruction memory, isn't written by the assembler at all —
`program_loader_pkg.vhd`'s loader (section 5) is the piece that fills those
remaining, never-assembled addresses with `nop` once it builds the CPU's
full ROM image.

---

## 8. Every bug found along the way, and why each fix works

This project's git history and comments record quite a few real bugs caught
during development — which is exactly the point of testing every module and
every seam in isolation before moving on. Here they all are, roughly in the
order they were found:

### 8.1 `severity error` doesn't fail the build
**Symptom:** a testbench with a genuinely wrong ALU result would print
`"INC 0 FAILED"` and then *still* print `"All tests passed."` right after.
**Root cause:** VHDL's `assert ... severity error` only prints a message; it
does not stop simulation. Only `severity failure` does that.
**Fix:** every assertion in the whole project uses `severity failure`.
Established at Step 1, applied retroactively to every testbench since.

### 8.2 `inc`'s test cases fed the wrong carry-in
**Symptom:** related to the fix above — while making that first example
testbench's failures actually visible, two of its `inc` (increment) test
cases turned out to be wrong themselves: they fed `CarryIn = '0'` directly
into the ALU bit-slice, but `inc` (`A + 1`) only produces the right answer
when the very first carry of the chain is seeded to `'1'` (see the ALU
section above).
**Fix:** seed `CarryIn = '1'` in those two test cases, matching how the ALU
is actually used for real (`alu32.vhd` does this seeding correctly) rather
than changing the expected results to match the wrong stimulus.

### 8.3 `lbs` (left shift) was a silent no-op in the first draft
**Symptom:** a first draft of `alu32.vhd` naively wired every bit slice's
input straight from the same-numbered bit of `OperandA`, for every opcode
uniformly — including the shift opcode. Since a single bit slice's shift
case just passes its input straight through (it *can't* shift on its own —
see the ALU section), this meant `lbs` silently did nothing at all: the
32-bit "shifted" result was identical to the original input.
**Root cause:** shifting is inherently a *cross-bit* operation, which no
individual 1-bit slice can perform by itself — only the wiring between
slices can.
**Fix:** `alu32.vhd` computes a separate "OperandA shifted left by one" view
up front (`OperandA(30 downto 0) & '0'`) and feeds *that* into the bit
slices' inputs specifically when the opcode is `lbs`, leaving every other
opcode's wiring untouched. Caught by a directed test
(`0xDEADBEEF << 1 = 0xBD5B7DDE`) before this bug could ever reach the full
CPU.

### 8.4 An off-by-one in a hand-typed zero-extension literal
**Symptom:** GHDL's own bounds-checking caught a hand-written 32-bit
zero-extend literal that actually only had 21 zero bits typed out (one
short), while wiring a preview of the fetch/PC-advance logic
(`alu32_instruction_memory_integration_tb.vhd`).
**Root cause:** manually counting zeros in a literal string is exactly the
kind of thing that's easy to get subtly wrong, especially at 20+ characters.
**Fix:** replaced the hand-typed literal with `resize(unsigned(...), 32)`,
which computes the correct width from two compile-time-constant numbers
instead of a human counting characters — a class of mistake that becomes
structurally impossible once you stop hand-counting bits.

### 8.5 A stray corrupted character broke `register_file.vhd`
**Symptom:** while working on the Program Counter Unit (Step 7), a bare
extra `1` character had landed in `register_file.vhd`, sitting right before
a comment, which broke that file's interface declaration and thus broke
compilation of everything depending on it.
**Fix:** removed the stray character. Unrelated to the step's actual work,
but worth recording since it briefly broke the whole build.

### 8.6 The `IoEnable` same-timestamp glitch
This is probably the subtlest bug in the whole project, and it's worth
walking through carefully because it's a genuinely instructive simulation
gotcha, not just a typo.

**Symptom:** `cpu_tb.vhd`, using a straightforward `wait until IoEnable =
'1'` to catch an IO transmission, caught a *spurious* one several cycles too
early — during an ordinary RAM store to address 50 (nowhere near the IO
address range at all, which starts at 128).

**Root cause:** `IoEnable` is computed as `MemoryWriteEnable and
IsIoAddress`. These two signals settle at very different speeds within a
single simulated instant: `MemoryWriteEnable` comes from a short combinational
path (fetched instruction → opcode → the control unit's case statement),
while `IsIoAddress` comes from a much longer one (fetched instruction →
register reads → sign-extension → the full 32-bit ripple-carry ALU → address
truncation). VHDL simulates one clock "instant" as potentially many tiny
internal steps called **delta cycles** — and within that one instant, before
everything has finished propagating, `MemoryWriteEnable` can already read
`'1'` while `IsIoAddress` still reflects a stale value left over from the
*previous* instruction, making the *product* of the two transiently read
`'1'` for a brief moment before the real, settled values take over.
`wait until X = '1'` is triggered by *events* (any change), so it happily
reports that fleeting, not-yet-settled transient as if it were the final
answer.

**Fix:** never use an event-triggered wait on `IoEnable`. Instead, sample it
**once per clock cycle**, a fixed short delay after each rising edge (`wait
until rising_edge(Clock); wait for 1 ns;`), giving every delta-cycle in that
instant time to fully settle before anything is read. This exact pattern —
already used everywhere else in the project for the same "let the
combinational chain settle" reason — is now a hard rule for anything
watching the CPU's `ioenable`/`ioaddress`/`iodata` ports.

### 8.7 A GHDL startup artifact that looks like a bug but isn't
**Symptom:** while writing an integration test chaining `RegisterFile` →
`Alu32` → `DataMemory`, GHDL printed `NUMERIC_STD.TO_INTEGER: metavalue
detected` at simulation time `0ms` — even though every relevant signal
already had an explicit `'0'` starting value.

**Root cause (confirmed by deliberately isolating and bisecting it in its
own tiny reproduction file,
`src/simulation-notes/metavalue_startup_artifact_demo_tb.vhd`):** this is an
inherent, one-delta-cycle artifact of how VHDL/GHDL elaborates a design —
any signal fed through even one concurrent assignment (as opposed to being
driven directly) doesn't actually carry its "driven" value until its driver
process has executed *at least once*, which hasn't happened yet at the very
first instant of time `0`. It's not caused by a missing initializer and it's
not a real correctness bug.

**Resolution:** this warning is scoped to `@0ms` only and self-resolves
within that same simulated instant; every testbench in this project already
only checks results after a nonzero `wait for ...`, so it never
contaminates a real assertion. The demo file exists specifically so that
**if this warning shows up again in any later testbench, nobody needs to
re-investigate it from scratch** — it just links back to this file. (A few
signals — `Alu32`'s `CarryChain`/`ResultInternal`, `RegisterFile`'s
`ReadData1`/`ReadData2` — were still given explicit `'0'` initializers
anyway as good, defensive practice, even though bisection showed that alone
doesn't actually stop the warning.)

### 8.8 A `store` operand-order bug while hand-writing the first test program
**Symptom:** the assembled machine code for `tools/programs/cpu_test_program.asm`
didn't match independently hand-computed expected values.
**Root cause:** as noted in the ISA section above, `store`'s documented
operand order is `(address register, data register, offset)` — the
*opposite* of `load`'s `(destination register, address register, offset)`.
The first draft of the test program wrote every `store` line with the data
register listed first, matching `load`'s order out of habit instead of
`store`'s actual order. The assembler itself worked correctly — it encoded
exactly what was written — the mistake was purely in the hand-written
assembly source.
**Fix:** rewrote the `store` lines with the correct operand order. Caught
by eye, by comparing the assembled hex against an independent by-hand
calculation — not caught automatically by any tool, which is exactly why
`tools/assemble_sieve.py` encodes each mnemonic according to its documented
semantic role instead of one generic "same order for everything" parser —
so that a mistake like this can only happen in the assembly *source*, never
silently inside the assembler's own logic.

### 8.9 The sieve program's own off-by-one bound bug
**Symptom (documented directly in `tools/programs/sieve_program.asm`):** an
early version of the sieve assembly loaded `r3 = 127` as the loop's upper
bound. But every loop in this program (`store r2 r1 0`'s initial-fill loop,
the prime-candidate scan, and the multiples-clearing loop) is written as an
**exclusive** bound — it stops as soon as the loop index *equals* `r3`,
without ever actually processing that value. Loading 127 meant every one of
those loops stopped one index short and never touched index 127 at all — so
127 was silently skipped both as a value to initialize/mark *and* as a
candidate to ever test or output as prime, even though 127 is prime and
within the intended 2–127 range.
**Fix:** load `r3 = 128` instead. Since every loop's bound is exclusive,
this makes 127 the last index actually visited by all three loops, correctly
covering the full inclusive range 2–127.

### 8.10 `cpu_tb.vhd` left pointed at the sieve program with stale, mismatched expectations
**Symptom:** `cpu_tb.vhd` was updated to load `sieve_program.bin` (the real
sieve) instead of the original `cpu_test_program.bin` (the small hand-built
test program used while building the CPU), but a leftover constant,
`ExpectedTransmissions`, still hardcoded the **old** test program's expected
register outputs (e.g. `128 → 30`, `129 → 20`, ...) — values that have
nothing to do with what the sieve program actually produces (a list of
primes). At the point this was noticed, the actual `assert`-against-
`ExpectedTransmissions` loop had already been stripped out of the process,
leaving that whole constant (and its two supporting `record`/`array` type
declarations) as unused dead code, and the testbench's header comments still
described it as doing hardcoded-expectation checking that it no longer
actually did.
**Root cause:** this is a natural side effect of the project deliberately
switching `cpu_tb.vhd` from "the CPU's one and only test program" to "a
generic runner, currently pointed at whichever program is interesting right
now" — the old assertion machinery, built for one specific fixed program,
doesn't generalize to "run any program and see what it does."
**Fix:** removed `ExpectedTransmissions` and its supporting types entirely,
and rewrote the header comment to describe what the file actually does now:
load whatever `.bin` file `TestProgram` points at, run it, and report every
`(IoAddress, IoData)` observed while `IoEnable = '1'` — with no hardcoded
expectations at all, so the same file can be pointed at *any* compiled
program and just tell you what it output, rather than asserting it matches
one specific program's results.

---

## 9. Dev environment & tooling

- **GHDL** (an open-source VHDL simulator) only runs inside a VS Code
  **devcontainer** — it is not installed on the host machine at all. The
  container image is intentionally minimal (see the FPGA-rollback story
  above): just `ghdl`, `make`, `git`, `sudo`, `curl` on `debian:bookworm-slim`.
- **The Makefile** (`make sim TB=<entity name>`) compiles every `.vhd` file
  under `src/` (excluding the throwaway `src/example/` tree) with `ghdl -a`,
  elaborates the requested testbench entity with `ghdl -e`, then runs it
  with `ghdl -r`, dumping a waveform to `waves/<entity>.vcd`. One Makefile
  subtlety: `program_loader_pkg.vhd` (the one VHDL *package* in the whole
  project) is explicitly listed first in the file list, because VHDL package
  analysis is order-dependent — a package must be compiled before anything
  that references it — unlike component instantiation, which only needs to
  resolve at elaboration time and doesn't care about compile order.
- **Waveform viewing** happens via the VaporView VS Code extension, reading
  the `.vcd` file `make sim` produces. (See the earlier conversation in this
  session for a walkthrough of how to actually read one of these waveforms —
  short version: the `ioaddress`/`iodata` bus carries *every* memory access,
  not just real IO output, so you need to also look at `ioenable` and only
  trust `iodata` on cycles where it's `'1'` and the address is ≥ 128.)
- **Assembling a program:**
  ```
  python3 tools/assemble_sieve.py tools/programs/sieve_program.asm \
      --binary-out tools/programs/sieve_program.listing.txt \
      --bits-out   tools/programs/sieve_program.bin
  ```
  `--bits-out` is the only file any testbench actually loads (plain 0/1
  text, one 32-character line per instruction); `--binary-out` is a
  human-readable listing (with the source line as a trailing comment) meant
  purely for a person to read, never for a testbench to consume.
  `.bin` files are git-ignored — they're a build output, regenerated from
  the `.asm` source, and never checked in.

---

## 10. Current status

Per the project's own living planning document
(`docs/cpu-implementation-plan.md`), every module (ALU, register file,
instruction memory, data memory, control unit, PC unit, the top-level `Cpu`,
the assembler, and the program-loading mechanism) is built and has passing
unit tests plus integration tests proving it cooperates correctly with
everything built before it — 14+ testbenches all green at time of writing.

The real Sieve of Eratosthenes program (`tools/programs/sieve_program.asm`,
primes 2–127) has been written, assembled, and — per the most recent commit,
`95d83fa "ran the primes"` — actually executed against the real `Cpu`
entity via `cpu_tb.vhd`. As part of that same commit, `cpu_tb.vhd` was
changed from "assert this one specific program's outputs exactly" into a
generic runner that simply reports every IO transmission it observes (see
bug 8.10 above for the cleanup that followed in this session).

One thing worth flagging: the planning document's own status checklist
(section 7) still shows Step 9 ("assemble the real sieve program") and Step
10 ("a dedicated `cpu_sieve_tb.vhd` that asserts the output equals the
golden prime list `2, 3, 5, 7, 11, ..., 127`") as **not yet checked off**,
even though the sieve program itself has already been run successfully. In
other words: the *hard part* (a correct CPU actually producing the right
primes) is done, but the originally-planned dedicated pass/fail testbench
(`cpu_sieve_tb.vhd`, asserting the captured IO sequence exactly equals the
31-prime golden list) doesn't exist yet as its own file — right now,
correctness of the sieve run has to be checked by eye (reading `cpu_tb.vhd`'s
report output or a waveform), not by an automated assertion. That would be
the natural next step if an automated, self-checking proof of the final
result is still wanted for the report/rubric.
