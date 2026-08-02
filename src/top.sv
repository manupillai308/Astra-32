import risc_pkg::*;

module top #(
  parameter RESET_PC = 32'h0000,
  parameter RAM_ADDR_WIDTH = 10,
  parameter LED_WIDTH = 3,
  parameter LED_BASE_ADDR = 32'h1000_0000,
  parameter UART_BASE_ADDR = 32'h1000_0010,
  parameter int CLK_HZ = 12_000_000,
  parameter int UART_BAUD = 115_200
)(
  input  logic                 clk,
  input  logic                 reset_n,
  output logic [LED_WIDTH-1:0] mmio_led,
  input logic uart_rx,
  output logic uart_tx
);

logic        cpu_dmem_req;
logic        cpu_dmem_wr_en;
mem_size_t   cpu_dmem_data_size;
logic [31:0] cpu_dmem_addr;
logic [31:0] cpu_dmem_wr_data;
logic        cpu_dmem_zero_extend;
logic [31:0] cpu_dmem_rd_data;

cpu #(
  .RESET_PC(RESET_PC)
) u_cpu (
  .clk              (clk),
  .reset_n          (reset_n),
  .dmem_req         (cpu_dmem_req),
  .dmem_wr_en       (cpu_dmem_wr_en),
  .dmem_data_size   (cpu_dmem_data_size),
  .dmem_addr        (cpu_dmem_addr),
  .dmem_wr_data     (cpu_dmem_wr_data),
  .dmem_zero_extend (cpu_dmem_zero_extend),
  .dmem_rd_data     (cpu_dmem_rd_data)
);

bus #(
  .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),
  .LED_WIDTH      (LED_WIDTH),
  .LED_BASE_ADDR  (LED_BASE_ADDR),
  .UART_BASE_ADDR (UART_BASE_ADDR),
  .CLK_HZ (CLK_HZ),
  .UART_BAUD (UART_BAUD)
) u_bus (
  .clk                  (clk),
  .reset_n              (reset_n),
  .cpu_dmem_req         (cpu_dmem_req),
  .cpu_dmem_wr_en       (cpu_dmem_wr_en),
  .cpu_dmem_data_size   (cpu_dmem_data_size),
  .cpu_dmem_addr        (cpu_dmem_addr),
  .cpu_dmem_wr_data     (cpu_dmem_wr_data),
  .cpu_dmem_zero_extend (cpu_dmem_zero_extend),
  .cpu_dmem_rd_data     (cpu_dmem_rd_data),
  .mmio_led             (mmio_led),
  .uart_rx (uart_rx),
  .uart_tx (uart_tx)
);

endmodule
