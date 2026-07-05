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
| `src/instruction_memory/instruction_memory.vhd` | 1024×32 async-read ROM. Contents are a **local placeholder constant** for now (a handful of distinct words at known addresses + `nop` everywhere else), not `sieve_program_pkg` — introducing the real package early would force solving VHDL package-analysis-order in the Makefile (packages must be analyzed before anything that `use`s them, unlike component-instantiated entities such as `ALUBitSlice`, which only bind at elaboration) twice for no benefit. Step 9 introduces `sieve_program_pkg.vhd` for real and switches this file over to it, fixing the ordering properly at that point. |
| `src/instruction_memory/instruction_memory_tb.vhd` | spot-check a few addresses (incl. the top of the range, 1023) against the placeholder constant, plus one unlisted address to confirm the `nop` default applies |
| `src/integration-tests/alu32_instruction_memory_integration_tb.vhd` | cross-module integration test previewing the PC-unit/instruction-fetch interaction ahead of Step 7: a plain signal stands in for the not-yet-built PC register, advanced each clock edge by feeding it through the real `Alu32` in `inc` mode, with the result driving the real `InstructionMemory`'s `Address` — checks addresses 0/1/2 fetch in order with the right placeholder words. (Caught a real bug via `ghdl`'s bound-check: a hand-written 22-zero-bit zero-extend literal for the ALU operand was miscounted at 21 bits; fixed with `resize(unsigned(...), 32)` instead, which can't be miscounted since both widths involved are compile-time constants, not runtime-variable sizing.) |
| `src/data_memory/data_memory.vhd` | 128×32 RAM + addr-range decode driving `ioaddress`/`iodata`/`ioenable`. Named `data_memory.vhd`/`DataMemory`, not `data_mem` — matches the `instruction_memory`/`register_file` full-name precedent. `IoAddress`/`IoData`/`IoEnable` are purely combinational (not registered): `IoEnable <= '1' when (MemoryWriteEnable = '1' and IsIoAddress = '1') else '0'`, gated by `IsIoAddress <= Address(7)`. The RAM write process additionally requires `IsIoAddress = '0'` before writing — this is the guard that stops an IO-range store from also corrupting RAM at the aliased low-7-bits index (e.g. storing to address 200 must not silently write RAM(72)). |
| `src/data_memory/data_memory_tb.vhd` | RAM read/write in range (ignored without `MemoryWriteEnable`, captured with it); ordinary RAM store doesn't raise `IoEnable`; IO-range store raises `IoEnable`/`IoAddress`/`IoData` correctly *and* is confirmed not to have written through to RAM at the aliased index |
| `src/integration-tests/register_file_alu32_data_memory_integration_tb.vhd` | cross-module integration test chaining all three completed modules for real `store`/`load`-shaped sequences: `RegisterFile` (rs/rt) → `Alu32` (address = rs + immediate, `OpCode` forced to add, matching the real control unit's future behaviour for memory ops) → `DataMemory` (RAM store, then a `load` reading it back, then a round trip through the register file's own write port) → a final IO-range store (address 130) checked both for the right `IoEnable` pulse and for not corrupting RAM at the aliased index (2). |
| `src/simulation-notes/metavalue_startup_artifact_demo_tb.vhd` | **Not a module test** — a minimal, deliberately isolated reproduction of a GHDL simulation-startup artifact found while writing the integration test above: any memory address fed through even one concurrent signal assignment (instead of being a directly-driven signal) prints `NUMERIC_STD.TO_INTEGER: metavalue detected` at `@0ms`, *even when every signal involved has an explicit `'0'` initial value* — confirmed by bisection to be an inherent one-delta-cycle artifact of VHDL/GHDL elaboration (a driven signal's first computed value isn't available until its driver executes at least once), not a bug in `RegisterFile`/`DataMemory`/`Alu32`. Scoped to `@0ms` only and self-resolves within the same simulation instant; every testbench in this project already only checks results after a nonzero `wait for ...`, so it never contaminates a real assertion. This file demonstrates that explicitly (asserts a correct read-back at `@11ns` despite the `@0ms` warning) so nobody re-investigates it from scratch or mistakes it for a real bug later. **If this warning appears in any future testbench's output, it does not need investigating** — link back to this file instead. |
| `src/control_unit/control_unit.vhd` | `OpCode`/`FunctionCode` → `{RegisterDestinationSelect, AluSourceSelect, AluOperandAZero, MemoryToRegisterSelect, RegisterWriteEnable, MemoryWriteEnable, BranchEnable, BranchOnZero, JumpEnable, AluOpCode}` — **one signal beyond the original sketch**: `AluOperandAZero`. `load immediate` needs the ALU to compute `0 OP immediate` so the result can ride the normal ALU-result write-back path, but this ISA's r0 is an ordinary register (not hardwired zero — section 2), so relying on "r0 happens to hold zero" would be a fragile, program-specific assumption instead of a real hardware guarantee. `AluOperandAZero` forces the ALU's first operand to zero generically, and `AluOpCode` is forced to `"011"` (or) for `load immediate` specifically so `0 or immediate = immediate`. `BranchOnZero` is the "zero-flag polarity" pc_unit.vhd will need: `'1'` for `beq` (take the branch when `ZeroFlag='1'`), `'0'` for `bne` (take it when `ZeroFlag='0'`) — both force `AluOpCode = "001"` (sub) so `ZeroFlag` reflects `rs = rt`. `RegisterWriteEnable`/`MemoryWriteEnable` are named to match `RegisterFile`/`DataMemory`'s own port names exactly, so `cpu.vhd` can wire them straight across. |
| `src/control_unit/control_unit_tb.vhd` | truth-table style: one assert block per instruction from the ISA table (R-type checked with 3 different `FunctionCode` values to prove pass-through rather than a hardcoded match), plus one unused/reserved opcode confirming a safe all-zero default |
| `src/integration-tests/control_unit_datapath_integration_tb.vhd` | capstone integration test for the whole non-branching/non-jumping datapath: a real `ControlUnit` drives real `RegisterFile` + `Alu32` + `DataMemory` instances through decoded `add`/`load immediate`/`store`/`load` instructions. **The `load immediate` case is the one that matters most**: it first seeds the instruction's (ISA-unused) `rs` field's register with nonzero garbage (`0xBADBADBA`), then confirms the write-back result is still exactly the immediate — proving `AluOperandAZero` is actually necessary and correct, not just a theoretical concern. |
| `src/pc_unit/pc_unit.vhd` | next-PC mux: sequential (+1) / branch (+signed imm, gated on `BranchEnable` & `ZeroFlag`/`BranchOnZero` polarity, via `BranchTaken <= BranchEnable and (ZeroFlag xnor BranchOnZero)` — plain `"="` on two `STD_LOGIC` values returns a `BOOLEAN`, which can't `and` with a `STD_LOGIC`, hence `xnor` instead) / jump (absolute, highest priority). **Contains no PC register itself** — purely combinational "what should the PC become next" logic; the actual clocked PC register lives in `cpu.vhd` (Step 8), the same separation `Alu32` has from any register that might store its result. |
| `src/pc_unit/pc_unit_tb.vhd` | sequential (incl. wraparound at PC=1023), taken/not-taken branch in both directions (forward and backward/loop), jump overriding an otherwise-satisfied branch condition |
| `src/integration-tests/pc_unit_control_unit_alu32_integration_tb.vhd` | cross-module integration test with a real `ControlUnit` + `Alu32` driving a real `PcUnit`, plus a clocked stand-in PC register (same "stand-in register, real logic" approach as Step 4's fetch-address preview) — drives a tiny hand-crafted `bne`/`bne`/`jump`/`add` sequence (loop taken, loop exited, then an unconditional jump, then an ordinary instruction) proving all three modules cooperate on real ALU-computed `ZeroFlag` values, not just directly-driven test signals like `pc_unit_tb.vhd` uses. |
| `src/cpu/cpu.vhd` | top-level structural wiring of all of the above; ports = exactly `clk, ioaddress, iodata, ioenable` |
| `src/cpu/cpu_tb.vhd` | small hand-written instruction sequences (one per instruction class: R-type, load/store, branch taken/not-taken, jump), asserts on register/memory state |
| `src/cpu/sieve_program_pkg.vhd` | constant array of 32-bit machine words = Appendix 3's program, generated by `tools/assemble_sieve.py` |
| `src/cpu/cpu_sieve_tb.vhd` | full integration test: run the real sieve program, capture every `(ioaddress, iodata)` while `ioenable='1'`, assert the captured sequence equals the golden prime list |
| `tools/assemble_sieve.py` | standalone script (outside `src/`, not picked up by the Makefile's VHDL glob) that encodes Appendix 3 into `sieve_program_pkg.vhd`, one line at a time, with the semantic-role mapping from section 2 spelled out per instruction — this doubles as report-methodology evidence for "how machine code was derived" |

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
- [ ] **Step 8** — `cpu.vhd` + `cpu_tb.vhd` (directed instruction-class tests)
- [ ] **Step 9** — `tools/assemble_sieve.py` + `sieve_program_pkg.vhd`
- [ ] **Step 10** — `cpu_sieve_tb.vhd` full integration test vs. golden prime list
