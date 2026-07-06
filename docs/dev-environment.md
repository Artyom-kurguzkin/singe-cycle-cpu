# How to use


requires using vscode devcontainer


<br>

```
make sim TB=AluBitSlice_tb 
```

* if passed, will populate `/work` & `/waves`. Running it again will rewrite previous attempt.

You can explore the waveofrm directly from here using installed VaporView extension. 

Note, for Claude Code to run correctly, requires WSL to run in mirrored (bridged) mode.

<br>

## Assembling a program and running a testbench against it

Programs are written as `.asm` source files (see `tools/programs/*.asm` for
examples) and compiled with `tools/assemble_sieve.py` into a plain binary
file — one instruction per line, each line 32 characters of `0`/`1`. This is
the only file format a testbench actually loads; the assembler never emits
VHDL.

```
python3 tools/assemble_sieve.py tools/programs/cpu_test_program.asm \
    --binary-out tools/programs/cpu_test_program.listing.txt \
    --bits-out   tools/programs/cpu_test_program.bin
```

* `--binary-out` is a human-readable listing (fields space-separated, one
  instruction per line, source line as a trailing comment) — for reading,
  not for consumption by any testbench.
* `--bits-out` is the actual compiled binary that gets loaded into
  `InstructionMemory`/`Cpu`'s `ProgramData` generic.

Regenerate the `.bin`/`.listing.txt` files any time the `.asm` source
changes — nothing does this automatically.

Loading the compiled binary into a simulation is entirely a testbench-side
concern (see `docs/cpu-implementation-plan.md` section 2b for the full
rationale): a testbench calls `ProgramLoaderPkg.LoadProgramFromFile` on the
`.bin` file to build a constant, then passes that constant in via a
`generic map` when instantiating `Cpu` (or `InstructionMemory` directly).
`cpu.vhd`/`instruction_memory.vhd` never read a file themselves. To point a
testbench at a different compiled program, edit the file path argument to
`LoadProgramFromFile` in that testbench, e.g. in `cpu_tb.vhd`:

```vhdl
constant TestProgram : STD_LOGIC_VECTOR (32767 downto 0) :=
    LoadProgramFromFile("tools/programs/cpu_test_program.bin");
```

Once the `.bin` file exists, run the testbench that consumes it the normal
way:

```
make sim TB=Cpu_tb
```

File paths passed to `LoadProgramFromFile` are resolved relative to the
working directory `ghdl -r` is invoked from — this project's `Makefile`
always runs it from the repo root, so paths like
`tools/programs/cpu_test_program.bin` resolve correctly as long as `make`
is run from `/workspace`. 