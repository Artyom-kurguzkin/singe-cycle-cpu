# CPU Implementation Plan & Design Spec

Living document for the ENGR3701 final project (32-bit CPU running a Sieve of
Eratosthenes program). Written so a future session — with none of this
conversation's context — can pick up exactly where things left off. Update
the **Status** section as steps complete; keep the rest of the doc as the
source of truth for design decisions so they never need re-deriving.

Source requirements: `docs/Project task description.pdf` (authoritative —
ISA, memory map, entity ports, rubric) and `docs/rubric and submission
details.png` (report rubric only). `docs/project - test program.pdf`
describes a **different, larger** sieve variant (primes 2-511, bigger memory,
a Nexys 3 board display module) — that is background/historical material
only, **not** this assignment's spec. Do not build against it.

## Scope decisions (already made, don't re-ask)

- Sieve range: **2–127** (main spec's memory map: 128-word RAM + 128-word IO).
- CPU style: **single-cycle** datapath (not multi-cycle/FSM).
- Course variant: **ENGR3701** — standard ripple-carry adder. Not
  ENGR9781/GE, so no carry-lookahead adder needed.
- **`src/example/` is off-limits for the real project.** It exists solely to
  validate the dev-environment tooling (GHDL/Makefile/testbench-severity
  conventions — see Step 1). It is never referenced, instantiated, or
  structurally mirrored by any file under `src/`. Every module the project
  needs — including the ALU bit-slice — is authored fresh directly under
  `src/`, even when the resulting design is conceptually similar to
  Practical 2's (the report can still say it's "based on" that practical;
  the VHDL itself is our own file, not a wrapper around the example). The
  Makefile's `VHDL_FILES` excludes `src/example/**` for exactly this reason —
  it also sidesteps entity-name collisions (e.g. both trees would otherwise
  define `ALUBitSlice`).

## 0b. Naming convention (applies to every new file under `src/`)

No short/cryptic identifiers (no `a`, `b`, `s`, `i`, `tmp`) — use full
descriptive names, C#-style. E.g. prefer
`OperandA`/`OperandB`/`Result`/`ZeroFlag`/`BitIndex` over `a`/`b`/`s`/`zero`/`i`.
Well-known domain acronyms (`ALU`, `PC`, `CPU`, `IO`) are fine as-is — the
rule targets single-letter/cryptic names, not standard terminology.

## 0c. Comment density (applies to every file under `src/`, retroactively too)

Comment **heavily** — every entity/port's purpose, every non-trivial signal,
every process/case branch, and the *why* behind each design choice (e.g. why
a port is dual-read, why a mux exists, why a carry-in is seeded a certain
way). This is a deliberate departure from a terser default: the report's
method section needs to describe the VHDL in detail, so heavily-commented
source doubles as that documentation. Apply this to already-written files
too, not just new ones going forward.

## 1. Instruction Set (from Appendix 1 & 2 of the task PDF)

### Formats (32 bits total)

| Format | Layout |
|---|---|
| R | `opcode(6) \| rs(4) \| rt(4) \| rd(4) \| funct(3) \| unused(11)` |
| I | `opcode(6) \| rs(4) \| rt(4) \| immediate(16) \| unused(2)` |
| J | `opcode(6) \| address(10) \| unused(16)` |

### Opcodes / functs

| Name | Type | Opcode | Funct | Semantics |
|---|---|---|---|---|
| add | R | 0x00 | 000 | rd = rs + rt |
| sub | R | 0x00 | 001 | rd = rs - rt |
| and | R | 0x00 | 010 | rd = rs and rt |
| or | R | 0x00 | 011 | rd = rs or rt |
| xor | R | 0x00 | 100 | rd = rs xor rt |
| not | R | 0x00 | 101 | rd = not rs |
| lbs | R | 0x00 | 110 | rd = rs shifted (see ALUBitSlice) |
| inc | R | 0x00 | 111 | rd = rs + 1 |
| load immediate | I | 0x22 | — | rt(15 downto 0) = immediate, zero-extended to 32 bits |
| load | I | 0x23 | — | rt = mem(rs + immediate) |
| store | I | 0x21 | — | mem(rs + immediate) = rt |
| beq | I | 0x05 | — | if rs==rt: pc += sign_extend(immediate(9 downto 0)) |
| bne | I | 0x04 | — | if rs!=rt: pc += sign_extend(immediate(9 downto 0)) |
| jump | J | 0x02 | — | pc = address (absolute, 10-bit word address) |
| nop | J | 0x3f | — | no-op |

**Funct values for R-type are identical to `ALUBitSlice`'s `Opcode` input**
(add=000 ... inc=111) — the control unit can pass funct straight through to
the ALU for R-type instructions with zero translation logic. For I-type
memory ops (load/store address calc), force ALU op to add (000).

## 2. Resolved ambiguities (derived by reading the spec text + reverse-engineering Appendix 3's assembly line-by-line — these are NOT obvious from a skim, record here so nobody re-derives them differently)

- **PC is word-addressed**, not byte-addressed (spec: "PC will treat each
  32-bit instruction as a single location"). PC increments by 1 per
  instruction. Branch/jump targets need **no ×4 shift** — a simplification
  vs. the textbook byte-addressed MIPS datapath.
- **R-type field order is `rs, rt, rd`** (matches the bit layout exactly:
  opcode|rs|rt|rd|funct). Verified against the one unambiguous 3-distinct-register
  example in Appendix 3, `sub r6 r3 r7`: this must mean rs=r6, rt=r3, **rd=r7**
  (a freshly-used scratch register, never read before this line) — if rd were
  first (typical MIPS mnemonic style `op rd,rs,rt`) this instruction would read
  an uninitialized r7 as an operand, which makes no sense in context.
- **`load`**: table says `mem($rs+immediate)->$rt` → rs=address register,
  rt=destination register. Confirmed via Appendix 3's `load r6 r2 0` — must
  load mem[r2] (loop index) into r6 (temp), since r2 is later compared/reused
  as the loop index and r6 is a fresh temp being tested.
- **`store`**: table says `$rt->mem($rs+immediate)` → rs=address register,
  rt=data source. Confirmed via `store r4 r2 0` (send prime r2 to IO pointer
  r4) and `store r6 r0 0` (clear non-prime at address r6 with value 0=r0).
  **Note the asymmetry**: load's assembly text lists (dest, addr, imm) while
  store's lists (addr, data, imm) — the two mnemonics don't share one uniform
  operand-order rule in the *example assembly text*. This doesn't matter for
  the actual hardware/encoding (the bit-field roles above are what's
  authoritative); it only matters if hand-transcribing Appendix 3 into machine
  code — see `tools/assemble_sieve.py`, which encodes by semantic role per
  line, not by a generic parser.
- **`load immediate`**: table says `immediate->$rt(15 downto 0)`. The
  register file only supports whole-word writes (no partial-word write port
  mentioned in spec), so in hardware this must zero-extend the 16-bit
  immediate into the full 32-bit destination register.
- **beq/bne**: register comparison is symmetric (order doesn't matter for
  equality). Only immediate bits(9 downto 0) are used, sign-extended, added
  to PC.
- **jump**: 10-bit address field = absolute word address into instruction
  memory (2^10 = 1024 = exact ROM size — clearly intentional).
- **Memory address space is 0–255** (8 bits): bit 7 = 0 → RAM (low 7 bits
  index 128 words, addr 0-127), bit 7 = 1 → memory-mapped IO (addr 128-255).
  Per spec, "the IO registers themselves do not need to be implemented" — so
  on a store targeting the IO range, do **not** write internal RAM; instead
  pulse `ioenable='1'` for that one cycle with `ioaddress`/`iodata` driven,
  and let external logic (in our case, the testbench) observe it. Reads from
  the IO address range are undefined/don't-care (spec doesn't require
  read-back; the program under test never does this).
- **CPU entity has exactly 4 ports**: `clk, ioaddress, iodata, ioenable` — no
  reset pin per spec. PC/registers get their t=0 value from VHDL signal
  initializers (`:= (others => '0')`), which GHDL honours; acceptable since
  this project is simulation-only (the FPGA bitstream toolchain was
  deliberately stripped from the devcontainer — see `.devcontainer/Dockerfile`
  git history).
- Signal widths not specified by the spec (a judgment call): `ioaddress` is
  8 bits (covers 0-255, values 128-255 meaningful when `ioenable='1'`),
  `iodata` is 32 bits (matches the datapath width throughout).

## 2b. Program-loading mechanism (how a compiled program gets into
InstructionMemory — settled at Step 8, after several false starts; record
the final design here so nobody re-derives it, or re-tries an already-ruled-out
alternative, later)

**Final design:**
- `InstructionMemory` (`instruction_memory.vhd`) takes its contents via a
  **generic**, `ProgramData : STD_LOGIC_VECTOR(32767 downto 0)` (1024 words
  × 32 bits, flattened into one wide bus — word `W` at bits
  `((W+1)*32-1) downto (W*32)`), with **no default value**. It has zero
  knowledge of files. `cpu.vhd` has the same generic, forwarded straight
  through to its internal `InstructionMemory` instance.
- `tools/assemble_sieve.py` (the assembler) outputs **plain machine code
  only** — never VHDL. Two output files: a human-readable binary listing
  (`--binary-out`, fields space-separated with the source line as a
  comment) and the actual compiled binary (`--bits-out`, one instruction
  per line, each line exactly 32 characters of `0`/`1`, nothing else).
- `program_loader_pkg.vhd` provides one function,
  `LoadProgramFromFile(FilePath : string) return STD_LOGIC_VECTOR`, that
  reads a `--bits-out` file into the flattened 32768-bit form. **This
  package, and the file-reading it does, is used exclusively by
  testbenches** (`cpu_tb.vhd`, `instruction_memory_tb.vhd`,
  `alu32_instruction_memory_integration_tb.vhd`) — never by `cpu.vhd` or
  `instruction_memory.vhd`. A testbench calls it once, at elaboration, to
  build a `constant`, then passes that constant in via the `ProgramData`
  generic when instantiating `Cpu`/`InstructionMemory`.

**Why this shape, specifically (each point below is something an earlier
attempt got wrong, keep it that way going forward):**
- **Not a hardcoded constant inside `instruction_memory.vhd`.** That was
  Step 4/8's original approach and meant hand-editing that file's source
  every time the program changed (test program now, the real Appendix 3
  sieve program at Step 9) — exactly the problem this mechanism exists to
  avoid.
- **Not read from a file *inside* `instruction_memory.vhd` or `cpu.vhd`.**
  `STD.TEXTIO` file I/O is inherently non-synthesizable (there is no
  real-silicon equivalent) — it has no business being part of a hardware
  description, not even as an "internal implementation detail" component
  wired invisibly inside `cpu.vhd`. A real ROM's contents are fixed at
  fabrication; a `generic` (resolved once at elaboration, never a live
  signal) is the hardware-honest way to model that, and it keeps every
  file reachable from `cpu.vhd`'s own structural body 100% synthesizable
  in spirit.
- **Not a compiled VHDL package per program**, e.g. a
  `sieve_program_pkg.vhd` holding `constant SievProgram : ... := (x"...",
  ...)`. A compiler/assembler should emit *machine code*, not another
  language's source code — and generating a `.vhd` file per program also
  reopens the VHDL package-analysis-ordering problem (packages must be
  analyzed before anything that `use`s them) for no benefit, since the
  binary-file approach sidesteps it entirely except for the one small
  loader package itself.
- **Not a custom array type** (e.g. `type InstructionArrayType is array (0
  to 1023) of STD_LOGIC_VECTOR(31 downto 0)`) **shared via its own
  package.** A custom type used across separately-compiled files still
  needs a package purely so every file agrees on the same type — flattening
  to a plain `STD_LOGIC_VECTOR` sidesteps that entirely, since
  `STD_LOGIC_VECTOR` is already predefined and visible everywhere. This is
  also why `program_loader_pkg.vhd` is the *only* package in this whole
  project: nothing else needs one.
- **The loader is a plain function, not an entity/component.** An entity
  version (`ProgramLoader`, instantiated inside `cpu.vhd`, driving
  `ProgramData` as an output port to `InstructionMemory`'s input port) was
  actually built and worked, but was still fake, non-synthesizable
  "hardware" sitting inside `cpu.vhd`'s structural body, wired via a
  runtime signal — which is exactly what the generic-based approach above
  avoids. A function, callable only from testbenches, has no such
  presence in the hardware description at all.
- **The function still needs to live in a package** (not be declared
  locally inside one testbench), purely because three separate testbenches
  need to call it and VHDL has no way to share a subprogram across files
  except via a package — this is not the same concern as the "custom
  array type" package problem above, and doesn't justify one.

**Consequence for Step 9/10:** the real sieve program never needs its own
VHDL package at all now — `tools/assemble_sieve.py` just gets pointed at
Appendix 3's `.asm` transcription to produce
`tools/programs/sieve_program.bin`, and `cpu_sieve_tb.vhd` loads it via the
exact same `ProgramLoaderPkg.LoadProgramFromFile` call `cpu_tb.vhd` already
uses, just with a different file path. The module map's earlier mention of
a `sieve_program_pkg.vhd` file is obsolete; ignore it if it still appears
anywhere stale.

## 3. Module map

Each module gets its own folder under `src/`, containing that module's
implementation + its own testbench (e.g. `src/alu/alu32.vhd` +
`src/alu/alu32_tb.vhd`). Cross-module integration testbenches that don't
belong to any single module live in `src/integration-tests/` instead. The
Makefile's recursive `find` already picks up any nesting depth, so this
needed no build-system change beyond the pre-existing `src/example/`
exclusion. `src/example/` itself is untouched, unused, excluded from the
build (see Scope decisions).

| File | Purpose |
|---|---|
| `src/alu/alu_bit_slice.vhd` | 1-bit ALU slice, own file under `src/` (not `src/example/`, not instantiating anything from there) — `Opcode`-driven case statement for add/sub/and/or/xor/not/lbs/inc, same shape as a textbook bit-slice ALU but authored independently |
| `src/alu/alu_bit_slice_tb.vhd` | directed per-opcode tests on the bit slice in isolation |
| `src/alu/alu32.vhd` | 32× `ALUBitSlice` chained (ripple carry) via a `generate` loop — carry-seed-on-sub/inc (`CarryChain(0) <= '1' when OpCode = "001" or OpCode = "111"`), `ZeroFlag` derivation, and **opcode-dependent bit wiring for `lbs`**: since a single bit slice can't shift itself (its `"110"` case just passes `InputA` through), `alu32.vhd` feeds slice `i`'s `InputA` from `OperandA(i - 1)` (zero-filled at bit 0) instead of `OperandA(i)` when `OpCode = "110"`, via an `EffectiveOperandA` mux ahead of the generate loop — this is what actually makes `lbs` shift instead of being a no-op |
| `src/alu/alu32_tb.vhd` | directed per-funct-code tests, `alu_bit_slice_tb.vhd` style |
| `src/register_file/register_file.vhd` | 16×32-bit, dual async read port, single sync (clocked) write port |
| `src/register_file/register_file_tb.vhd` | write/read-back on both ports, simultaneous dual-read check (same reg on both ports, and two different regs at once) |
| `src/integration-tests/register_file_alu32_integration_tb.vhd` | cross-module integration test: wires a real `RegisterFile` + `Alu32` together (no mocks) and drives a short hand-written "instruction" sequence (seed two registers, `add`, then a chained `sub` off the `add`'s result) end-to-end, proving the two already-built modules actually cooperate correctly before they get buried inside `cpu.vhd`. **Pattern going forward:** add a small integration testbench like this one whenever a new module can be meaningfully wired to an already-completed one, rather than deferring all cross-module testing to `cpu_tb.vhd`/`cpu_sieve_tb.vhd` at the very end — bugs at the seams are much cheaper to find here. |
| `src/instruction_memory/instruction_memory.vhd` | 1024×32 async-read ROM. Takes its contents via the `ProgramData` generic (see section 2b) — no hardcoded program, no file access, no default value. At Step 4 this was 4 arbitrary placeholder words hardcoded in the body; at Step 8 it became this generic-based design once a real, swappable test program was needed. |
| `src/instruction_memory/instruction_memory_tb.vhd` | plays the "loader" itself (`ProgramLoaderPkg.LoadProgramFromFile`, see section 2b) to build a `constant` from `tools/programs/cpu_test_program.bin`, passes it via generic map, then spot-checks a few addresses (incl. the top of the range, 1023, and the program's last instruction) against the assembled program, plus one unlisted address to confirm the loader's `nop` fill applies |
| `tools/programs/cpu_test_program.asm` | hand-written assembly source for the test program, in Appendix-3-compatible syntax (labels, `--` comments) — exercises R-type add/sub, load-immediate, a store/load round trip, a taken `beq`, a taken `bne`, a not-taken `bne`, and an absolute `jump`, then stores 10 registers out to IO addresses 128-137 so `cpu_tb.vhd` can verify the whole run purely through `cpu.vhd`'s external ports (see `cpu_tb.vhd`'s entry below for why), ending in a self-jump steady-state loop like Appendix 3's `#label4`. **Caught a real bug**: `store`'s documented operand order is `(addr, data, imm)` — opposite of `load`'s `(dest, addr, imm)` (section 2's asymmetry) — and the first draft of this file wrote every `store` line with the *data* register first, matching `load`'s order instead of `store`'s. The assembler encoded exactly what was written (correctly) with the operands swapped; the mistake was caught by eye when the resulting hex didn't match independently hand-computed values, not by any tool. |
| `tools/programs/cpu_test_program.listing.txt`, `tools/programs/cpu_test_program.bin` | generated outputs of `tools/assemble_sieve.py` run against the `.asm` file above — the human-readable binary listing and the actual compiled machine code (loaded by `ProgramLoaderPkg.LoadProgramFromFile`), respectively. Regenerate with: `python3 tools/assemble_sieve.py tools/programs/cpu_test_program.asm --binary-out tools/programs/cpu_test_program.listing.txt --bits-out tools/programs/cpu_test_program.bin` |
| `src/integration-tests/alu32_instruction_memory_integration_tb.vhd` | cross-module integration test previewing the PC-unit/instruction-fetch interaction ahead of Step 7: a plain signal stands in for the not-yet-built PC register, advanced each clock edge by feeding it through the real `Alu32` in `inc` mode, with the result driving the real `InstructionMemory`'s `Address` — checks addresses 0/1/2 fetch in order with the right words (also plays the "loader" role itself, same as `instruction_memory_tb.vhd` above). (Caught a real bug via `ghdl`'s bound-check: a hand-written 22-zero-bit zero-extend literal for the ALU operand was miscounted at 21 bits; fixed with `resize(unsigned(...), 32)` instead, which can't be miscounted since both widths involved are compile-time constants, not runtime-variable sizing.) |
| `src/data_memory/data_memory.vhd` | 128×32 RAM + addr-range decode driving `ioaddress`/`iodata`/`ioenable`. Named `data_memory.vhd`/`DataMemory`, not `data_mem` — matches the `instruction_memory`/`register_file` full-name precedent. `IoAddress`/`IoData`/`IoEnable` are purely combinational (not registered): `IoEnable <= '1' when (MemoryWriteEnable = '1' and IsIoAddress = '1') else '0'`, gated by `IsIoAddress <= Address(7)`. The RAM write process additionally requires `IsIoAddress = '0'` before writing — this is the guard that stops an IO-range store from also corrupting RAM at the aliased low-7-bits index (e.g. storing to address 200 must not silently write RAM(72)). |
| `src/data_memory/data_memory_tb.vhd` | RAM read/write in range (ignored without `MemoryWriteEnable`, captured with it); ordinary RAM store doesn't raise `IoEnable`; IO-range store raises `IoEnable`/`IoAddress`/`IoData` correctly *and* is confirmed not to have written through to RAM at the aliased index |
| `src/integration-tests/register_file_alu32_data_memory_integration_tb.vhd` | cross-module integration test chaining all three completed modules for real `store`/`load`-shaped sequences: `RegisterFile` (rs/rt) → `Alu32` (address = rs + immediate, `OpCode` forced to add, matching the real control unit's future behaviour for memory ops) → `DataMemory` (RAM store, then a `load` reading it back, then a round trip through the register file's own write port) → a final IO-range store (address 130) checked both for the right `IoEnable` pulse and for not corrupting RAM at the aliased index (2). |
| `src/simulation-notes/metavalue_startup_artifact_demo_tb.vhd` | **Not a module test** — a minimal, deliberately isolated reproduction of a GHDL simulation-startup artifact found while writing the integration test above: any memory address fed through even one concurrent signal assignment (instead of being a directly-driven signal) prints `NUMERIC_STD.TO_INTEGER: metavalue detected` at `@0ms`, *even when every signal involved has an explicit `'0'` initial value* — confirmed by bisection to be an inherent one-delta-cycle artifact of VHDL/GHDL elaboration (a driven signal's first computed value isn't available until its driver executes at least once), not a bug in `RegisterFile`/`DataMemory`/`Alu32`. Scoped to `@0ms` only and self-resolves within the same simulation instant; every testbench in this project already only checks results after a nonzero `wait for ...`, so it never contaminates a real assertion. This file demonstrates that explicitly (asserts a correct read-back at `@11ns` despite the `@0ms` warning) so nobody re-investigates it from scratch or mistakes it for a real bug later. **If this warning appears in any future testbench's output, it does not need investigating** — link back to this file instead. |
| `src/control_unit/control_unit.vhd` | `OpCode`/`FunctionCode` → `{RegisterDestinationSelect, AluSourceSelect, ImmediateZeroExtend, AluOperandAZero, MemoryToRegisterSelect, RegisterWriteEnable, MemoryWriteEnable, BranchEnable, BranchOnZero, JumpEnable, AluOpCode}` — **two signals beyond the original sketch**. `AluOperandAZero`: `load immediate` needs the ALU to compute `0 OP immediate` so the result can ride the normal ALU-result write-back path, but this ISA's r0 is an ordinary register (not hardwired zero — section 2), so relying on "r0 happens to hold zero" would be a fragile, program-specific assumption instead of a real hardware guarantee — this forces the ALU's first operand to zero generically, and `AluOpCode` is forced to `"011"` (or) for `load immediate` specifically so `0 or immediate = immediate`. `ImmediateZeroExtend` (added at Step 8, while writing `cpu.vhd`'s sign/zero-extension logic): the 16-bit immediate field means two different things depending on opcode — `load immediate` zero-extends it (ISA table: `immediate->$rt(15 downto 0)`), while `load`/`store` address calculation sign-extends it (standard MIPS convention, since an offset can be negative) — both share the same `AluSourceSelect = '1'` path into the ALU, so `cpu.vhd` needs this bit to know which extension to apply. `'1'` only for `load immediate`; `'0'` (sign-extend) everywhere else. `BranchOnZero` is the "zero-flag polarity" pc_unit.vhd needs: `'1'` for `beq` (take the branch when `ZeroFlag='1'`), `'0'` for `bne` (take it when `ZeroFlag='0'`) — both force `AluOpCode = "001"` (sub) so `ZeroFlag` reflects `rs = rt`. `RegisterWriteEnable`/`MemoryWriteEnable` are named to match `RegisterFile`/`DataMemory`'s own port names exactly, so `cpu.vhd` can wire them straight across. |
| `src/control_unit/control_unit_tb.vhd` | truth-table style: one assert block per instruction from the ISA table (R-type checked with 3 different `FunctionCode` values to prove pass-through rather than a hardcoded match), plus one unused/reserved opcode confirming a safe all-zero default |
| `src/integration-tests/control_unit_datapath_integration_tb.vhd` | capstone integration test for the whole non-branching/non-jumping datapath: a real `ControlUnit` drives real `RegisterFile` + `Alu32` + `DataMemory` instances through decoded `add`/`load immediate`/`store`/`load` instructions. **The `load immediate` case is the one that matters most**: it first seeds the instruction's (ISA-unused) `rs` field's register with nonzero garbage (`0xBADBADBA`), then confirms the write-back result is still exactly the immediate — proving `AluOperandAZero` is actually necessary and correct, not just a theoretical concern. |
| `src/pc_unit/pc_unit.vhd` | next-PC mux: sequential (+1) / branch (+signed imm, gated on `BranchEnable` & `ZeroFlag`/`BranchOnZero` polarity, via `BranchTaken <= BranchEnable and (ZeroFlag xnor BranchOnZero)` — plain `"="` on two `STD_LOGIC` values returns a `BOOLEAN`, which can't `and` with a `STD_LOGIC`, hence `xnor` instead) / jump (absolute, highest priority). **Contains no PC register itself** — purely combinational "what should the PC become next" logic; the actual clocked PC register lives in `cpu.vhd` (Step 8), the same separation `Alu32` has from any register that might store its result. |
| `src/pc_unit/pc_unit_tb.vhd` | sequential (incl. wraparound at PC=1023), taken/not-taken branch in both directions (forward and backward/loop), jump overriding an otherwise-satisfied branch condition |
| `src/integration-tests/pc_unit_control_unit_alu32_integration_tb.vhd` | cross-module integration test with a real `ControlUnit` + `Alu32` driving a real `PcUnit`, plus a clocked stand-in PC register (same "stand-in register, real logic" approach as Step 4's fetch-address preview) — drives a tiny hand-crafted `bne`/`bne`/`jump`/`add` sequence (loop taken, loop exited, then an unconditional jump, then an ordinary instruction) proving all three modules cooperate on real ALU-computed `ZeroFlag` values, not just directly-driven test signals like `pc_unit_tb.vhd` uses. |
| `src/instruction_memory/program_loader_pkg.vhd` | the loading mechanism (section 2b): one function, `LoadProgramFromFile(FilePath : string) return STD_LOGIC_VECTOR`, reading a `--bits-out` machine-code file into the flattened 32768-bit form. **Testbench-only** — `cpu.vhd`/`instruction_memory.vhd` never reference this package. The only package in the whole project, needed purely because three different testbenches share this one function. |
| `src/cpu/cpu.vhd` | top-level structural wiring of all of the above; ports = exactly `clk, ioaddress, iodata, ioenable`, plus a `ProgramData` generic (elaboration-time only, not a port, so it doesn't violate the spec's port list) forwarded straight into the internal `InstructionMemory` instance's own generic. Owns the two things no single module owns: the actual clocked `ProgramCounter` register (`PcUnit` only computes what it should become next — see that file's header comment) and the instruction-field extraction/sign-extension logic (`OpCode`/`RsField`/`RtField`/`RdField`/`FunctionCode`/`RawImmediate`/`JumpAddressField`, all sliced directly from `FetchedInstruction` per section 1's format tables — `SignExtendedImmediate`/`ZeroExtendedImmediate` computed via `resize(signed/unsigned(RawImmediate), 32)`, muxed by `ImmediateZeroExtend`). |
| `src/cpu/cpu_tb.vhd` | the "loader": calls `ProgramLoaderPkg.LoadProgramFromFile("tools/programs/cpu_test_program.bin")` itself to build a `constant`, passes it via `Cpu`'s `ProgramData` generic map, then runs the full test program and verifies the outcome **purely by observing the external `ioaddress`/`iodata`/`ioenable` ports** — no internal signal access, no debug ports, matching the spec's actual mechanism for reporting results. Samples `IoEnable` once per clock cycle, 1 ns after each rising edge — **not** with `wait until IoEnable = '1'` (see the note on the `IoEnable` glitch below). |
| `tools/assemble_sieve.py` | two-pass assembler (labels resolved in pass 1, encoding in pass 2), built at **Step 8** (moved forward from its originally-planned Step 9 slot) once `cpu_tb.vhd` needed a real, nontrivial, branch/jump-heavy test program and hand-computing offsets by hand became error-prone. Encodes each mnemonic by its documented semantic role (section 2's `load`-vs-`store` operand-order asymmetry, `R`-type's uniform `rs rt rd` per Appendix 3's own convention even for `not`/`lbs`/`inc`), not with one generic parser. Reads a `.asm` source file (comments `--`, labels `#name`) and emits **two plain-machine-code output files, never VHDL** (see section 2b for why): `--binary-out` (human-readable, fields space-separated, source line as a trailing comment) and `--bits-out` (the actual compiled binary — one instruction per line, each line exactly 32 characters of `0`/`1`). Validates branch offsets fit the 10-bit signed field and jump/immediate values fit their encoding width, erroring out clearly instead of silently truncating. Will be reused as-is for Appendix 3's real sieve program at Step 9 (just a different `.asm` input, producing `tools/programs/sieve_program.bin`). |
| `src/cpu/cpu_sieve_tb.vhd` | full integration test (Step 10): loads `tools/programs/sieve_program.bin` via the same `ProgramLoaderPkg.LoadProgramFromFile` call `cpu_tb.vhd` uses, runs the real sieve program, captures every `(ioaddress, iodata)` while `ioenable='1'`, asserts the captured sequence equals the golden prime list — same cycle-sampling approach as `cpu_tb.vhd`, for the same `IoEnable`-glitch reason. No VHDL package for the sieve program is needed (section 2b). |

## 4. Testbench conventions (established, follow for every new testbench)

Discovered while fixing the existing example: `AluBitSlice_tb.vhd` used
`severity error` on its assertions, which does **not** halt GHDL simulation —
so a failing assertion prints e.g. `INC 0 FAILED` and the simulation just
continues on to print `All tests passed.` regardless, which is a lie.

**Rule going forward: every assertion in every testbench uses `severity
failure`, never `severity error` or `severity warning`.** `severity failure`
halts the simulation immediately at the first failing check and makes
`ghdl -r` (and therefore `make sim`) return a non-zero exit code — a failing
test must actually fail the build, not just print text that might get missed
or, worse, get overridden by an unconditional trailing report.

(Fixed already in `src/example/AluBitSlice_tb.vhd`, which also had a real bug:
its two `inc` test cases fed `CarryIn='0'` directly into the bit-slice, but
`inc` only produces `+1` when the carry chain is seeded with `CarryIn='1'` —
which is what `alu_toplevel.vhd` does correctly for real usage. Fixed by
seeding `CarryIn='1'` in those two `apply(...)` calls, matching real usage
instead of changing the expected outputs.)

**Rule for anything watching `cpu.vhd`'s `ioenable`/`ioaddress`/`iodata`
ports (established while writing `cpu_tb.vhd`, Step 8): never use `wait
until IoEnable = '1'` (or any raw event-triggered wait on it) — sample it
once per clock cycle instead, a fixed short delay after each rising edge
(`wait until rising_edge(Clock); wait for 1 ns;`), the same settling-margin
idiom every other testbench in this project already uses.** Reason:
`IoEnable <= MemoryWriteEnable and IsIoAddress` (`data_memory.vhd`), and
these two operands settle at very different speeds — `MemoryWriteEnable`
through a short path (`InstructionMemory` → `OpCode` → `ControlUnit`'s case
statement), `IsIoAddress` through a long one (`InstructionMemory` →
register reads → sign-extension → the 32-bit ripple-carry `Alu32` →
truncation). Within one simulated instant (many delta-cycles, one
timestamp), `IoEnable` can transiently read `'1'` before the address has
actually finished settling — and `wait until` is edge/event-triggered, so
it happily reports that same-timestamp transient as if it were the real
value. `cpu_tb.vhd` hit this directly: a `wait until IoEnable = '1'` fired
on a spurious transient during an ordinary RAM `store` (address 50, not an
IO address at all) several cycles before any real IO transmission should
have occurred. Sampling once per cycle after a 1 ns margin skips past all
of that instant's delta-cycle activity before ever reading the signal.
`cpu_sieve_tb.vhd` (Step 10) needs this exact same pattern.

## 5. Golden reference for the final integration test

Primes 2–127 (31 values), derived from the Appendix 4/5 Python reference in
the task PDF, with that reference's leading `0, 1` entries dropped (they're
an artifact of `numpy.ones()` never marking indices 0/1 as composite — this
assembly program's loop structure starts candidates at 2 and never emits 0 or
1 to the IO bus):

```
2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71,
73, 79, 83, 89, 97, 101, 103, 107, 109, 113, 127
```

`cpu_sieve_tb.vhd` should capture every `(ioaddress, iodata)` pair observed
while `ioenable='1'` during the run and assert the `iodata` sequence equals
this list in order. Bound the simulation at a generous fixed cycle count
(e.g. 20000 — comfortably above the program's actual instruction-execution
count for a 127-entry sieve). Mark this bound with a `-- ponytail:` comment
noting it's a deliberate simplification (fixed cycle count vs. detecting the
program's `#label4: jump #label4` steady-state loop) and can be raised if the
program hasn't finished by then.

## 6. How to actually run things

GHDL only exists inside the devcontainer, not on the Windows host. If the
current shell is already inside the devcontainer (check: `which ghdl`
succeeds), just run `make sim TB=<entity>` directly — no `docker exec` needed.

Only reach for Docker from a shell that is on the host, outside the
container:

```
docker ps --filter "label=devcontainer.local_folder=<repo path>" --format "{{.ID}} {{.Status}}"
docker start <container_id>          # if not already Up
docker exec <container_id> bash -c "cd /workspace && make sim TB=<entity>"
```

Container IDs change across rebuilds — look it up by the
`devcontainer.local_folder` label rather than reusing a stale ID.

## 7. Status

- [x] **Step 1** — Fixed `Makefile`'s `VHDL_FILES` to recursively find
      `.vhd` files (was `$(wildcard $(SRCDIR)/*.vhd)`, non-recursive, matched
      nothing since all example files live under `src/example/`). Verified
      `make sim TB=AluBitSlice_tb` compiles and runs against
      `src/example/`, confirming the devcontainer/GHDL toolchain works. Also
      fixed the pre-existing `inc`-carry-in bug and `severity
      error`→`failure` in `src/example/AluBitSlice_tb.vhd` (section 4) —
      purely to validate the tooling; `src/example/` was never meant to be
      reused beyond that (see Scope decisions). Once Step 2 needed a real
      `ALUBitSlice`, `VHDL_FILES` was narrowed to
      `find $(SRCDIR) -name '*.vhd' -not -path '$(SRCDIR)/example/*'` so the
      example tree is fully excluded from the real build.
- [x] **Step 2** — `alu_bit_slice.vhd` + `alu_bit_slice_tb.vhd` (own,
      independent 1-bit ALU slice — see Scope decisions on why this isn't
      `src/example/ALUBitSlice.vhd`) and `alu32.vhd` + `alu32_tb.vhd` (32-bit
      word ALU, ripple-carry chain of the above via `generate`, with the
      opcode-dependent `lbs` shift-wiring fix described in section 3 — the
      first draft naively widened the example's uniform per-bit wiring and
      that made `lbs` a silent no-op, caught by directed testing before it
      could propagate into the CPU). Ports/signals use full descriptive
      names per section 0b, e.g.
      `OperandA`/`OperandB`/`Result`/`ZeroFlag`/`CarryChain`/`BitIndex`. No
      `overflow`/`compl_overflow` outputs — nothing downstream in this
      project's CPU needs unsigned/signed overflow (only `ZeroFlag`, for
      beq/bne). Verified `make sim TB=AluBitSlice_tb` and `make sim
      TB=alu32_tb` both pass (directed per-opcode tests, incl. full-width
      carry-propagation wraparound for add/inc and a correctness check on
      the `lbs` shift value/MSB discard). All source files in this step were
      retroactively given heavy explanatory comments per section 0c.
- [x] **Step 3** — `register_file.vhd` + `register_file_tb.vhd` (write
      ignored without `RegisterWriteEnable`, write-then-readback, and
      simultaneous dual-read of both two-different-registers and
      same-register cases) + `register_file_alu32_integration_tb.vhd` (new:
      first cross-module integration test — see the module-map entry above
      for what it drives and why this pattern is worth repeating for later
      steps). Verified `make sim TB=RegisterFile_tb` and `make sim
      TB=RegisterFileAlu32IntegrationTb` both pass.
- [x] **Step 4** — `instruction_memory.vhd` + `instruction_memory_tb.vhd`
      (local placeholder program constant, not `sieve_program_pkg` yet — see
      the module-map entry above for why) +
      `alu32_instruction_memory_integration_tb.vhd` (integration test
      previewing the PC-unit/instruction-fetch interaction using a plain
      signal as a stand-in PC register — see module-map entry). Verified
      `make sim TB=InstructionMemory_tb` and `make sim
      TB=Alu32InstructionMemoryIntegrationTb` both pass.
- **Reorg (after Step 4)** — moved every module into its own folder under
  `src/` (e.g. `src/alu/alu32.vhd` + `src/alu/alu32_tb.vhd`), with
  cross-module integration testbenches collected under `src/integration-tests/`
  instead of living next to any one module. No Makefile changes were needed
  — `VHDL_FILES`'s recursive `find` already handles arbitrary nesting, and
  component-based instantiation (used everywhere so far) doesn't care about
  file/folder layout, only entity names. Re-verified all six existing
  testbenches still pass after the move. This folder-per-module layout is
  now the convention for every remaining step below — the module-map paths
  above already reflect it.
- [x] **Step 5** — `data_memory.vhd` + `data_memory_tb.vhd` (renamed from
      the original `data_mem`/`instr_mem` shorthand to match the
      `instruction_memory`/`register_file` full-name precedent already set)
      + `register_file_alu32_data_memory_integration_tb.vhd` (the three-way
      integration test — see module-map entry for what it drives). Also
      produced `src/simulation-notes/metavalue_startup_artifact_demo_tb.vhd`,
      a deliberate, non-module demo documenting a benign GHDL `@0ms`
      startup warning discovered while writing the integration test (see
      its own module-map entry — **read that before spending time on this
      warning again if it resurfaces in a later step**). Also added
      explicit `'0'` initial values to `Alu32`'s internal `CarryChain`/
      `ResultInternal` and `RegisterFile`'s `ReadData1`/`ReadData2` output
      ports — good practice regardless (matches the defined-startup-state
      convention already used for `Registers`/`Ram`), though bisection
      showed the `@0ms` warning is not actually caused by any missing
      initializer (see the demo file). Verified `make sim TB=DataMemory_tb`,
      `make sim TB=RegisterFileAlu32DataMemoryIntegrationTb`, and `make sim
      TB=MetavalueStartupArtifactDemo_tb` all pass (the latter two print the
      documented benign warning; this is expected, not a regression).
- [x] **Step 6** — `control_unit.vhd` + `control_unit_tb.vhd` (added
      `AluOperandAZero` beyond the original signal sketch — see the
      module-map entry above for why `load immediate` needs it) +
      `control_unit_datapath_integration_tb.vhd` (capstone integration test
      driving the real `RegisterFile`/`Alu32`/`DataMemory` trio from real
      `ControlUnit` decode output across 4 instruction types; specifically
      proves `AluOperandAZero` is necessary via a garbage-seeded `rs`
      register — see module-map entry). Verified `make sim
      TB=ControlUnit_tb` and `make sim
      TB=ControlUnitDatapathIntegrationTb` both pass (the latter prints the
      documented benign `@0ms` metavalue warning — expected, not a
      regression).
- [x] **Step 7** — `pc_unit.vhd` + `pc_unit_tb.vhd` +
      `pc_unit_control_unit_alu32_integration_tb.vhd` (see module-map
      entries above for details). Note en route: a stray corrupted
      character had landed in `register_file.vhd` (a bare `1` before a
      comment, breaking the interface declaration) — fixed before
      continuing; unrelated to this step's actual work but worth noting
      since it briefly broke the build. Verified `make sim TB=PcUnit_tb`
      and `make sim TB=PcUnitControlUnitAlu32IntegrationTb` both pass, and
      re-ran the full regression (all 13 testbenches) clean.
- [x] **Step 8** — `cpu.vhd` (top-level structural wiring; owns the PC
      register and instruction-field extraction/sign-extension — see
      module-map entry) + `cpu_tb.vhd` (full-program run, verified purely
      via external IO ports). Along the way: added `ImmediateZeroExtend` to
      `ControlUnit` (see that file's module-map entry); built
      `tools/assemble_sieve.py` early (moved forward from Step 9) plus
      `tools/programs/cpu_test_program.asm`, once hand-computing branch/jump
      offsets for a real test program got error-prone (caught a real
      operand-order bug in the `.asm` source this way — see
      `instruction_memory.vhd`'s module-map entry); discovered and
      documented the `IoEnable` same-timestamp glitch and the "sample once
      per cycle" rule (section 4) that both `cpu_tb.vhd` and the future
      `cpu_sieve_tb.vhd` need. **Also went through several iterations on
      how a compiled program actually gets into `InstructionMemory`**
      before landing on the generic-based, testbench-only-loading design —
      see section 2b for the final shape and, importantly, the list of
      specific alternatives already tried and ruled out (hardcoded
      constant, file I/O inside the hardware description, one VHDL package
      per program, a custom array type, a `ProgramLoader` hardware
      component) so nobody re-attempts one of those later. `Instructions`
      is no longer hardcoded in `instruction_memory.vhd` at all —
      `tools/assemble_sieve.py` now only emits plain machine code (no
      VHDL), and `program_loader_pkg.vhd` (the one package in this project)
      provides the loading function every testbench calls. Verified `make
      sim TB=Cpu_tb`, `make sim TB=InstructionMemory_tb`, and `make sim
      TB=Alu32InstructionMemoryIntegrationTb` all pass with the final
      design, and re-ran the full regression (all 14 testbenches) clean.
- [ ] **Step 9** — `tools/assemble_sieve.py` (already built at Step 8;
      this step is now just "run it against Appendix 3") produces
      `tools/programs/sieve_program.bin` — **no VHDL package needed**
      (section 2b already ruled that out; ignore any earlier mention of
      `sieve_program_pkg.vhd`, which is obsolete)
- [ ] **Step 10** — `cpu_sieve_tb.vhd` full integration test vs. golden
      prime list, loading `sieve_program.bin` via the same
      `ProgramLoaderPkg.LoadProgramFromFile` call `cpu_tb.vhd` already uses
