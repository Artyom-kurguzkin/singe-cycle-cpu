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

## 3. Module map (new files under `src/`; `src/example/` untouched, unused,
excluded from the build)

| File | Purpose |
|---|---|
| `alu_bit_slice.vhd` | 1-bit ALU slice, own file under `src/` (not `src/example/`, not instantiating anything from there) — `Opcode`-driven case statement for add/sub/and/or/xor/not/lbs/inc, same shape as a textbook bit-slice ALU but authored independently |
| `alu_bit_slice_tb.vhd` | directed per-opcode tests on the bit slice in isolation |
| `alu32.vhd` | 32× `ALUBitSlice` chained (ripple carry) via a `generate` loop — carry-seed-on-sub/inc (`CarryChain(0) <= '1' when OpCode = "001" or OpCode = "111"`), `ZeroFlag` derivation, and **opcode-dependent bit wiring for `lbs`**: since a single bit slice can't shift itself (its `"110"` case just passes `InputA` through), `alu32.vhd` feeds slice `i`'s `InputA` from `OperandA(i - 1)` (zero-filled at bit 0) instead of `OperandA(i)` when `OpCode = "110"`, via an `EffectiveOperandA` mux ahead of the generate loop — this is what actually makes `lbs` shift instead of being a no-op |
| `alu32_tb.vhd` | directed per-funct-code tests, `AluBitSlice_tb.vhd` style |
| `regfile.vhd` | 16×32-bit, dual async read port, single sync (clocked) write port |
| `regfile_tb.vhd` | write/read-back on both ports, simultaneous dual-read check |
| `instr_mem.vhd` | 1024×32 async-read ROM, contents = `sieve_program_pkg` constant |
| `instr_mem_tb.vhd` | spot-check a few addresses against the package constant |
| `data_mem.vhd` | 128×32 RAM + addr-range decode driving `ioaddress`/`iodata`/`ioenable` |
| `data_mem_tb.vhd` | RAM read/write in range; IO-range store doesn't touch RAM, correctly pulses IO signals |
| `control_unit.vhd` | opcode/funct → {RegDst, ALUSrc, MemToReg, RegWrite, MemWrite, Branch, Jump, ALUOp} |
| `control_unit_tb.vhd` | truth-table style: one assert block per opcode |
| `pc_unit.vhd` | next-PC mux: sequential (+1) / branch (+signed imm, gated on Branch & zero-flag polarity) / jump (absolute) |
| `pc_unit_tb.vhd` | sequential, taken/not-taken branch, jump |
| `cpu.vhd` | top-level structural wiring of all of the above; ports = exactly `clk, ioaddress, iodata, ioenable` |
| `cpu_tb.vhd` | small hand-written instruction sequences (one per instruction class: R-type, load/store, branch taken/not-taken, jump), asserts on register/memory state |
| `sieve_program_pkg.vhd` | constant array of 32-bit machine words = Appendix 3's program, generated by `tools/assemble_sieve.py` |
| `cpu_sieve_tb.vhd` | full integration test: run the real sieve program, capture every `(ioaddress, iodata)` while `ioenable='1'`, assert the captured sequence equals the golden prime list |
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
      beq/bne). Verified `make sim TB=alu_bit_slice_tb` and `make sim
      TB=alu32_tb` both pass (directed per-opcode tests, incl. full-width
      carry-propagation wraparound for add/inc and a correctness check on
      the `lbs` shift value/MSB discard).
- [ ] **Step 3** — `regfile.vhd` + `regfile_tb.vhd`
- [ ] **Step 4** — `instr_mem.vhd` + `instr_mem_tb.vhd` (placeholder program)
- [ ] **Step 5** — `data_mem.vhd` + `data_mem_tb.vhd`
- [ ] **Step 6** — `control_unit.vhd` + `control_unit_tb.vhd`
- [ ] **Step 7** — `pc_unit.vhd` + `pc_unit_tb.vhd`
- [ ] **Step 8** — `cpu.vhd` + `cpu_tb.vhd` (directed instruction-class tests)
- [ ] **Step 9** — `tools/assemble_sieve.py` + `sieve_program_pkg.vhd`
- [ ] **Step 10** — `cpu_sieve_tb.vhd` full integration test vs. golden prime list
