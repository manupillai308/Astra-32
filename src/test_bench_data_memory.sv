module test_bench_data_memory();

  // ----------------------------------------------------------------
  // Harness parameters
  //   Tests report completion through LED MMIO:
  //     1 = pass
  //     2 = fail
  //   MAX_CYCLES: safety net so a buggy program can't loop forever.
  // ----------------------------------------------------------------
  parameter int MAX_CYCLES = 1_000_000;
  localparam int LED_WIDTH = 3;
  localparam logic [LED_WIDTH-1:0] TEST_PASS_LED = 3'h1;
  localparam logic [LED_WIDTH-1:0] TEST_FAIL_LED = 3'h2;
  // Sv32 tests need separate 4 KiB root and level-0 page tables.
  localparam int RAM_ADDR_WIDTH = 14;
  localparam int CLK_HZ = 100_000_000;
  localparam int UART_BAUD = 115_200;
  localparam int UART_CLKS_PER_BIT = CLK_HZ / UART_BAUD;
  localparam int UART_MAX_CAPTURED_BYTES = 256;
  parameter int RAM_STALL_CYCLES = 2;

  logic clk;
  logic reset_n;
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

  always #5 clk = ~clk;

  top_data_memory #(
    .RESET_PC(32'h0),
    .RAM_BASE_ADDR(32'h8000_0000),
    .LED_WIDTH(LED_WIDTH),
    .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
    .CLK_HZ(CLK_HZ),
    .UART_BAUD(UART_BAUD),
    .RAM_STALL_CYCLES(RAM_STALL_CYCLES)
  ) dut (
    .clk(clk),
    .reset_n(reset_n),
    .mmio_led(mmio_led),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx)
  );

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (reset_n && mmio_led == TEST_PASS_LED) begin
      $display("[PASS] pass LED detected at cycle %0d", cycle_count);
      $finish;
    end

    if (reset_n && mmio_led == TEST_FAIL_LED) begin
      $display("[FAIL] fail LED detected at cycle %0d (test code %0d)",
               cycle_count, dut.u_cpu.u_register_file.regs[31]);
      $finish;
    end

    if (cycle_count >= MAX_CYCLES) begin
      $display("[FAIL] timeout after %0d cycles", MAX_CYCLES);
      $finish;
    end
  end

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

  initial begin
    clk = 0;
    reset_n = 0;
    uart_rx = 1;
    #10 reset_n = 1;
  end

endmodule
