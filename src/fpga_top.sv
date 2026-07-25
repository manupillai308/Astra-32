module fpga_top #(
  parameter HEARTBEAT_BIT = 23
)(
  input  logic       clk,
  input  logic       reset_n,
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
  .RAM_ADDR_WIDTH (6),
  .LED_WIDTH      (3),
  .LED_BASE_ADDR  (32'h1000_0000)
) u_top (
  .clk      (clk),
  .reset_n  (reset_n),
  .mmio_led (mmio_led)
);

assign led[0]   = heartbeat_counter[HEARTBEAT_BIT];
assign led[3:1] = mmio_led;

endmodule
