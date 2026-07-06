-- Sieve of Eratosthenes (Appendix 3 program), primes 2-127.
-- r0 - zero  r1 - one  r2 - working value  r3 - target  r4 - prime offset
-- r5 - loop counter  r6 - temp1  r8 - sign test

load immediate r0 0
load immediate r1 1
load immediate r2 1
load immediate r3 128 --bug fix: r3 is used everywhere as an EXCLUSIVE upper bound (loops stop as soon as the index equals r3, without testing that index). Loading 127 here meant every loop -- the initial fill, the prime-candidate scan, and the multiple-clearing bound check -- stopped one short and never touched index 127 at all, so 127 was silently skipped both as a candidate to mark/initialize and as a prime to output. Loading 128 instead makes 127 the last index actually processed by all three loops, matching the intended inclusive range 2-127.
load immediate r4 128
load immediate r8 2048 --Set the contents of working memory to 1
#label1
store r2 r1 0
inc r2 r2 r2
bne r2 r3 #label1 --Start the algorithm at index 1. Finish at 513
load immediate r2 1
#label2
inc r2 r2 r2
beq r2 r3 #label4
load r6 r2 0
bne r6 r1 #label2 --Send prime to the IO bus
store r4 r2 0
inc r4 r4 r4 --Clear all multiples of the prime
load immediate r6 0
add r6 r2 r6
#label3
add r6 r2 r6 --The calculated index may exceed the maximum value, but we lack a branch on greater than. Subtract and check to see if the number is negative -- this could be performed by checking the msb, but here we only test bit 11 - which should be more significant than our mathematical operations.
sub r6 r3 r7
and r7 r8 r7
bne r7 r8 #label2 --clear the non-prime value; fixed the bug. was beq 
store r6 r0 0
jump #label3
--Loop endlessly
#label4
jump #label4
