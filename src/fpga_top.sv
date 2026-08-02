module fpga_top #(
  parameter HEARTBEAT_BIT = 23,
  parameter int CLK_HZ = 12_000_000,
  parameter int UART_BAUD = 115_200
)(
  input  logic       clk,
  input  logic       reset_n,
  input logic uart_rx,
  output logic uart_tx,
  output logic [3:0] led
);

logic [HEARTBEAT_BIT:0] heartbeat_counter;
logic [2:0]             mmio_led;

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) heartbeat_counter <= '0;
  else          heartbeat_counter <= heartbeat_counter + 1'b1;
end

top #(
  .RESET_PC       (32'h0000),
  .RAM_ADDR_WIDTH (12),
  .LED_WIDTH      (3),
  .LED_BASE_ADDR  (32'h1000_0000),
  .UART_BASE_ADDR (32'h1000_0010),
  .CLK_HZ (CLK_HZ),
  .UART_BAUD(UART_BAUD)
) u_top (
  .clk      (clk),
  .reset_n  (reset_n),
  .mmio_led (mmio_led),
  .uart_rx (uart_rx),
  .uart_tx (uart_tx)
);

assign led[0]   = heartbeat_counter[HEARTBEAT_BIT];
assign led[3:1] = mmio_led;

endmodule
