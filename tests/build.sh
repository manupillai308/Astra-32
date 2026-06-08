# riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o smoke.o smoke.s
# riscv64-unknown-elf-ld -m elf32lriscv  -T ../link.ld -o smoke.elf smoke.o
# riscv64-unknown-elf-objcopy -O binary smoke.elf smoke.bin
# od -An -tx1 -v -w4 smoke.bin | tr -d ' ' > smoke.mem
# vsim -c -voptargs="+acc" -do "run -all; quit" +PROGRAM=tests/smoke/smoke.mem +OUTDIR=tests/smoke/  test_bench
for t in fibonacci find_max bubble_sort; do
  (cd tests/$t && \
   riscv64-unknown-elf-as -march=rv32i -mabi=ilp32 -o $t.o $t.s && \
   riscv64-unknown-elf-ld -m elf32lriscv -T ../link.ld -o $t.elf $t.o && \
   riscv64-unknown-elf-objcopy -O binary $t.elf $t.bin && \
   od -An -tx1 -v -w4 $t.bin > $t.mem)
done