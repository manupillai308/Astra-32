module test_bench();

  // ----------------------------------------------------------------
  // Harness parameters
  //   HALT_ADDR : DMEM byte address the program writes to signal "done".
  //               Convention: last word of the 64-byte DMEM (0x3C).
  //   MAX_CYCLES: safety net so a buggy program can't loop forever.
  // ----------------------------------------------------------------
  parameter int HALT_ADDR  = 60;       // 0x3C
  // Bumped from 1000: pipelined-serialized mode is ~5 cycles per
  // instruction, so bubble_sort (~200 insts) now needs ~1000 just to halt.
  parameter int MAX_CYCLES = 5000;

  logic   clk;
  logic   reset_n;
  integer cycle_count = 0;

  // 10-time-unit clock period
  always #5 clk = ~clk;

  top #(.RESET_PC(32'h0)) dut (
    .clk(clk),
    .reset_n(reset_n)
  );

  // ----------------------------------------------------------------
  // Halt detection + timeout
  //   The program signals completion by storing a non-zero value at
  //   DMEM[HALT_ADDR]. If that never happens within MAX_CYCLES the
  //   test fails.
  // ----------------------------------------------------------------
  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (reset_n &&
        dut.u_data_memory.mem[HALT_ADDR] !== 8'h00 &&
        dut.u_data_memory.mem[HALT_ADDR] !== 8'hxx) begin
      $display("[PASS] halt detected at cycle %0d (dmem[0x%0h]=0x%0h)",
               cycle_count, HALT_ADDR, dut.u_data_memory.mem[HALT_ADDR]);
      dump_state();
      $finish;
    end

    if (cycle_count >= MAX_CYCLES) begin
      $display("[FAIL] timeout after %0d cycles", MAX_CYCLES);
      dump_state();
      $finish;
    end
  end

  // ----------------------------------------------------------------
  // dump_state
  //   Writes the final register file and data memory to per-test
  //   output files. OUTDIR is provided via +OUTDIR=<path> plusarg
  //   (defaults to current directory).
  //   $writememh produces ASCII hex that downstream `diff` can
  //   compare against captured golden files.
  // ----------------------------------------------------------------
  task dump_state;
    string outdir;
    if (!$value$plusargs("OUTDIR=%s", outdir)) outdir = ".";
    $writememh({outdir, "/actual_regs.hex"}, dut.u_register_file.regs);
    $writememh({outdir, "/actual_dmem.hex"}, dut.u_data_memory.mem);
  endtask

  // ----------------------------------------------------------------
  // Reset sequence
  // ----------------------------------------------------------------
  initial begin
    clk     = 0;
    reset_n = 0;
    #10 reset_n = 1;
  end

endmodule
