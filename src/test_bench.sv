module test_bench();

  // ----------------------------------------------------------------
  // Harness parameters
  //   HALT_ADDR : DMEM byte address the program writes to signal "done".
  //               Convention: last word of the 64-byte DMEM (0x3C).
  //   MAX_CYCLES: safety net so a buggy program can't loop forever.
  // ----------------------------------------------------------------
  parameter int HALT_ADDR  = 60;       // 0x3C
  // UART tests need ~1040 cycles per transmitted byte at 12 MHz / 115200 baud.
  parameter int MAX_CYCLES = 10000;
  localparam int LED_WIDTH = 3;
  localparam int RAM_ADDR_WIDTH = 12;
  localparam int DMEM_BYTES = 2**RAM_ADDR_WIDTH;
  localparam int UART_CLKS_PER_BIT = 12_000_000 / 115_200;
  localparam int UART_MAX_CAPTURED_BYTES = 256;
  parameter int RAM_STALL_CYCLES = 2;

  logic   clk;
  logic   reset_n;
  integer cycle_count = 0;
  logic [LED_WIDTH-1:0] mmio_led;
  logic uart_rx;
  logic uart_tx;
  logic [7:0] uart_tx_bytes [0:UART_MAX_CAPTURED_BYTES-1];
  integer uart_tx_count = 0;

  typedef enum logic [1:0] {
    UART_MON_IDLE = 2'b00,
    UART_MON_DATA = 2'b01,
    UART_MON_STOP = 2'b10
  } uart_mon_state_t;

  uart_mon_state_t uart_mon_state;
  integer          uart_sample_count;
  logic [2:0]      uart_bit_index;
  logic [7:0]      uart_tx_byte;

  // 10-time-unit clock period
  always #5 clk = ~clk;

  top #(
    .RESET_PC(32'h0),
    .LED_WIDTH(LED_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .RAM_STALL_CYCLES(RAM_STALL_CYCLES)
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .mmio_led(mmio_led),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
  );

  function automatic logic [7:0] dmem_byte(input int unsigned byte_addr);
    unique case (byte_addr[1:0])
      2'b00: dmem_byte = dut.u_bus.u_data_memory.mem[byte_addr[31:2]][7:0];
      2'b01: dmem_byte = dut.u_bus.u_data_memory.mem[byte_addr[31:2]][15:8];
      2'b10: dmem_byte = dut.u_bus.u_data_memory.mem[byte_addr[31:2]][23:16];
      default: dmem_byte = dut.u_bus.u_data_memory.mem[byte_addr[31:2]][31:24];
    endcase
  endfunction

  // ----------------------------------------------------------------
  // Halt detection + timeout
  //   The program signals completion by storing a non-zero value at
  //   DMEM[HALT_ADDR]. If that never happens within MAX_CYCLES the
  //   test fails.
  // ----------------------------------------------------------------
  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (reset_n &&
        dmem_byte(HALT_ADDR) !== 8'h00 &&
        dmem_byte(HALT_ADDR) !== 8'hxx) begin
      $display("[PASS] halt detected at cycle %0d (dmem[0x%0h]=0x%0h)",
               cycle_count, HALT_ADDR, dmem_byte(HALT_ADDR));
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
  // UART TX capture
  //   Decodes the top-level UART TX pin back into bytes and writes
  //   actual_uart_tx.hex for comparison/capture by the test harness.
  // ----------------------------------------------------------------
  always @(negedge clk or negedge reset_n) begin
    if (!reset_n) begin
      uart_mon_state    <= UART_MON_IDLE;
      uart_sample_count <= 0;
      uart_bit_index    <= '0;
      uart_tx_byte      <= '0;
      uart_tx_count     <= 0;
    end else begin
      unique case (uart_mon_state)
        UART_MON_IDLE: begin
          if (uart_tx == 1'b0) begin
            uart_mon_state    <= UART_MON_DATA;
            uart_sample_count <= UART_CLKS_PER_BIT + (UART_CLKS_PER_BIT / 2) - 1;
            uart_bit_index    <= '0;
            uart_tx_byte      <= '0;
          end
        end

        UART_MON_DATA: begin
          if (uart_sample_count == 0) begin
            uart_tx_byte[uart_bit_index] <= uart_tx;
            if (uart_bit_index == 3'd7) begin
              uart_mon_state    <= UART_MON_STOP;
              uart_sample_count <= UART_CLKS_PER_BIT - 1;
            end else begin
              uart_bit_index    <= uart_bit_index + 1'b1;
              uart_sample_count <= UART_CLKS_PER_BIT - 1;
            end
          end else begin
            uart_sample_count <= uart_sample_count - 1;
          end
        end

        UART_MON_STOP: begin
          if (uart_sample_count == 0) begin
            if (uart_tx_count < UART_MAX_CAPTURED_BYTES) begin
              uart_tx_bytes[uart_tx_count] <= uart_tx_byte;
              uart_tx_count <= uart_tx_count + 1;
            end
            uart_mon_state <= UART_MON_IDLE;
          end else begin
            uart_sample_count <= uart_sample_count - 1;
          end
        end

        default: begin
          uart_mon_state <= UART_MON_IDLE;
        end
      endcase
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
    integer dmem_file;
    integer led_file;
    integer uart_file;
    integer i;
    if (!$value$plusargs("OUTDIR=%s", outdir)) outdir = ".";
    $writememh({outdir, "/actual_regs.hex"}, dut.u_cpu.u_register_file.regs);

    dmem_file = $fopen({outdir, "/actual_dmem.hex"}, "w");
    if (dmem_file) begin
      for (i = 0; i < DMEM_BYTES; i = i + 1) begin
        $fdisplay(dmem_file, "%02h", dmem_byte(i));
      end
      $fclose(dmem_file);
    end else begin
      $display("[WARN] could not open %s", {outdir, "/actual_dmem.hex"});
    end

    led_file = $fopen({outdir, "/actual_led.hex"}, "w");
    if (led_file) begin
      $fdisplay(led_file, "%0h", mmio_led);
      $fclose(led_file);
    end else begin
      $display("[WARN] could not open %s", {outdir, "/actual_led.hex"});
    end

    uart_file = $fopen({outdir, "/actual_uart_tx.hex"}, "w");
    if (uart_file) begin
      for (i = 0; i < uart_tx_count; i = i + 1) begin
        $fdisplay(uart_file, "%02h", uart_tx_bytes[i]);
      end
      $fclose(uart_file);
    end else begin
      $display("[WARN] could not open %s", {outdir, "/actual_uart_tx.hex"});
    end
  endtask

  // ----------------------------------------------------------------
  // Reset sequence
  // ----------------------------------------------------------------
  initial begin
    clk     = 0;
    reset_n = 0;
    uart_rx = 1;
    #10 reset_n = 1;
  end

endmodule
