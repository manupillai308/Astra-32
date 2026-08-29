`timescale 1ps/1ps

module test_bench();

  // ----------------------------------------------------------------
  // Harness parameters
  //   Tests report completion through LED MMIO:
  //     1 = pass
  //     2 = fail
  //   MAX_CYCLES counts CPU clock cycles.
  // ----------------------------------------------------------------
  parameter int MAX_CYCLES = 1_000_000;
  localparam int LED_WIDTH = 3;
  localparam logic [LED_WIDTH-1:0] TEST_PASS_LED = 3'h1;
  localparam logic [LED_WIDTH-1:0] TEST_FAIL_LED = 3'h2;
  localparam int CLK_HZ = 100_000_000;
  localparam int UART_BAUD = 115_200;
  localparam int UART_CLKS_PER_BIT = CLK_HZ / UART_BAUD;
  localparam int UART_MAX_CAPTURED_BYTES = 256;

  logic clk_100mhz;
  logic clk_12mhz;
  logic reset_n;
  integer cycle_count = 0;
  logic uart_rx;
  logic uart_tx;
  logic [3:0] led;
  logic [LED_WIDTH-1:0] mmio_led;
  logic [7:0] uart_tx_bytes [0:UART_MAX_CAPTURED_BYTES-1];
  integer uart_tx_count = 0;

  wire [15:0] ddr3_dq;
  wire [1:0]  ddr3_dqs_n;
  wire [1:0]  ddr3_dqs_p;
  wire [13:0] ddr3_addr;
  wire [2:0]  ddr3_ba;
  wire        ddr3_ras_n;
  wire        ddr3_cas_n;
  wire        ddr3_we_n;
  wire        ddr3_reset_n;
  wire [0:0]  ddr3_ck_p;
  wire [0:0]  ddr3_ck_n;
  wire [0:0]  ddr3_cke;
  wire [0:0]  ddr3_cs_n;
  wire [1:0]  ddr3_dm;
  wire [0:0]  ddr3_odt;

  wire soc_clk = clk_100mhz;
  wire soc_reset_n = dut.soc_reset_n;

  typedef enum logic [1:0] {
    UART_MON_IDLE = 2'b00,
    UART_MON_DATA = 2'b01,
    UART_MON_STOP = 2'b10
  } uart_mon_state_t;

  uart_mon_state_t uart_mon_state;
  integer          uart_sample_count;
  logic [2:0]      uart_bit_index;
  logic [7:0]      uart_tx_byte;

  assign mmio_led = led[3:1];

  // 100 MHz and 12 MHz board clocks, in ps.
  always #5000  clk_100mhz = ~clk_100mhz;
  always #41667 clk_12mhz = ~clk_12mhz;

  fpga_top #(
    .CLK_HZ(CLK_HZ),
    .UART_BAUD(UART_BAUD)
  ) dut (
    .clk_100mhz(clk_100mhz),
    .clk_12mhz(clk_12mhz),
    .reset_n(reset_n),
    .ddr3_dqs_n(ddr3_dqs_n),
    .ddr3_dq(ddr3_dq),
    .ddr3_dqs_p(ddr3_dqs_p),
    .ddr3_addr(ddr3_addr),
    .ddr3_ba(ddr3_ba),
    .ddr3_ras_n(ddr3_ras_n),
    .ddr3_cas_n(ddr3_cas_n),
    .ddr3_we_n(ddr3_we_n),
    .ddr3_reset_n(ddr3_reset_n),
    .ddr3_ck_p(ddr3_ck_p),
    .ddr3_ck_n(ddr3_ck_n),
    .ddr3_cke(ddr3_cke),
    .ddr3_cs_n(ddr3_cs_n),
    .ddr3_dm(ddr3_dm),
    .ddr3_odt(ddr3_odt),
    .uart_rx(uart_rx),
    .uart_tx(uart_tx),
    .led(led)
  );

  ddr3_model u_ddr3_model (
    .rst_n(ddr3_reset_n),
    .ck(ddr3_ck_p[0]),
    .ck_n(ddr3_ck_n[0]),
    .cke(ddr3_cke[0]),
    .cs_n(ddr3_cs_n[0]),
    .ras_n(ddr3_ras_n),
    .cas_n(ddr3_cas_n),
    .we_n(ddr3_we_n),
    .dm_tdqs(ddr3_dm),
    .ba(ddr3_ba),
    .addr(ddr3_addr),
    .dq(ddr3_dq),
    .dqs(ddr3_dqs_p),
    .dqs_n(ddr3_dqs_n),
    .tdqs_n(),
    .odt(ddr3_odt[0])
  );

  // ----------------------------------------------------------------
  // Halt detection + timeout
  // ----------------------------------------------------------------
  always @(posedge soc_reset_n) begin
    $display("[INFO] SoC reset released at %0t", $time);
  end

  always @(posedge soc_clk) begin
    cycle_count <= cycle_count + 1;

    if (soc_reset_n && mmio_led == TEST_PASS_LED) begin
      $display("[PASS] pass LED detected at cycle %0d", cycle_count);
      $finish;
    end

    if (soc_reset_n && mmio_led == TEST_FAIL_LED) begin
      $display("[FAIL] fail LED detected at cycle %0d", cycle_count);
      $finish;
    end

    if (cycle_count >= MAX_CYCLES) begin
      $display("[FAIL] timeout after %0d cycles", MAX_CYCLES);
      $finish;
    end
  end

  // ----------------------------------------------------------------
  // UART TX capture
  // ----------------------------------------------------------------
  always @(negedge soc_clk or negedge soc_reset_n) begin
    if (!soc_reset_n) begin
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
    clk_100mhz = 0;
    clk_12mhz = 0;
    reset_n = 0;
    uart_rx = 1;
    #200000 reset_n = 1;
  end

endmodule
