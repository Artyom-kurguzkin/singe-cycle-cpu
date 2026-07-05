-- Hand-written test program for cpu_tb.vhd (Step 8), exercising every
-- instruction class: R-type arithmetic, load-immediate, store/load, a
-- taken beq, a taken bne, a not-taken bne, and an absolute jump. Since
-- cpu.vhd's only externally-visible ports are clk/ioaddress/iodata/
-- ioenable, the tail of this program stores every interesting register out
-- to the memory-mapped IO range (128 and up) so the testbench can verify
-- the whole run purely by observing those external ports -- the same
-- technique the real sieve program (Appendix 3) uses to report primes.

load immediate r0 0
load immediate r1 10
load immediate r2 20
add r1 r2 r3
sub r3 r1 r4
store r0 r4 50
load r5 r0 50

beq r1 r1 #beq_landing
load immediate r6 77
#beq_landing
load immediate r7 99

bne r1 r2 #bne_taken_landing
load immediate r8 111
#bne_taken_landing
load immediate r9 222

bne r1 r1 2
load immediate r10 333
load immediate r11 444

jump #jump_landing
load immediate r13 666
load immediate r13 777
load immediate r13 888
#jump_landing
load immediate r12 555

store r0 r3 128
store r0 r4 129
store r0 r5 130
store r0 r6 131
store r0 r7 132
store r0 r8 133
store r0 r9 134
store r0 r10 135
store r0 r12 136
store r0 r13 137

#steady_state_loop
jump #steady_state_loop
