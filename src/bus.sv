import risc_pkg::*;

module bus #(
  parameter RAM_ADDR_WIDTH = 6,
  parameter LED_WIDTH = 3,
  parameter LED_BASE_ADDR = 32'h1000_0000,
  parameter UART_BASE_ADDR = 32'h1000_0010,
  parameter int CLK_HZ = 12_000_000,
  parameter int UART_BAUD = 115_200
)(
  input  logic                 clk,
  input  logic                 reset_n,

  input  logic                 cpu_dmem_req,
  input  logic                 cpu_dmem_wr_en,
  input  mem_size_t            cpu_dmem_data_size,
  input  logic [31:0]          cpu_dmem_addr,
  input  logic [31:0]          cpu_dmem_wr_data,
  input  logic                 cpu_dmem_zero_extend,
  output logic [31:0]          cpu_dmem_rd_data,

  output logic [LED_WIDTH-1:0] mmio_led,

  input logic uart_rx,
  output logic uart_tx
);

logic ram_sel;
logic led_sel;
logic uart_sel;
logic ram_req;
logic led_req;
logic uart_req;

logic [31:0] ram_rd_data;
logic [31:0] led_rd_data;
logic [31:0] uart_rd_data;

typedef enum logic [1:0] {
  READ_TARGET_NONE = 2'b00,
  READ_TARGET_RAM  = 2'b01,
  READ_TARGET_LED  = 2'b10,
  READ_TARGET_UART = 2'b11
} read_target_t;

read_target_t read_target_q;

assign ram_sel = (cpu_dmem_addr[31:RAM_ADDR_WIDTH] == '0);
assign led_sel = (cpu_dmem_addr == LED_BASE_ADDR);
assign uart_sel = (cpu_dmem_addr[31:4] == UART_BASE_ADDR[31:4]);

always_comb begin
  ram_req = 1'b0;
  led_req = 1'b0;
  uart_req = 1'b0;

  unique case (1'b1)
    ram_sel: ram_req = cpu_dmem_req;
    led_sel: led_req = cpu_dmem_req;
    uart_sel: uart_req = cpu_dmem_req;
    default: begin
    end
  endcase
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    read_target_q <= READ_TARGET_NONE;
  end else if (cpu_dmem_req && !cpu_dmem_wr_en) begin
    unique case (1'b1)
      ram_sel: read_target_q <= READ_TARGET_RAM;
      led_sel: read_target_q <= READ_TARGET_LED;
      uart_sel: read_target_q <= READ_TARGET_UART;
      default: read_target_q <= READ_TARGET_NONE;
    endcase
  end
end

always_comb begin
  unique case (read_target_q)
    READ_TARGET_RAM:  cpu_dmem_rd_data = ram_rd_data;
    READ_TARGET_LED:  cpu_dmem_rd_data = led_rd_data;
    READ_TARGET_UART: cpu_dmem_rd_data = uart_rd_data;
    default:          cpu_dmem_rd_data = 32'h0;
  endcase
end

data_memory #(
  .ADDR_WIDTH(RAM_ADDR_WIDTH)
) u_data_memory (
  .clk              (clk),
  .dmem_req         (ram_req),
  .dmem_wr_en       (cpu_dmem_wr_en),
  .dmem_data_size   (cpu_dmem_data_size),
  .dmem_addr        (cpu_dmem_addr),
  .dmem_wr_data     (cpu_dmem_wr_data),
  .dmem_zero_extend (cpu_dmem_zero_extend),
  .dmem_rd_data     (ram_rd_data)
);

mmio_led #(
  .LED_WIDTH(LED_WIDTH)
) u_mmio_led (
  .clk     (clk),
  .reset_n (reset_n),
  .req     (led_req),
  .wr_en   (cpu_dmem_wr_en),
  .wr_data (cpu_dmem_wr_data),
  .rd_data (led_rd_data),
  .led     (mmio_led)
);

mmio_uart #(
  .CLK_HZ(CLK_HZ),
  .BAUD(UART_BAUD)
) u_mmio_uart (
  .clk(clk),
  .reset_n(reset_n),
  .req(uart_req),
  .wr_en(cpu_dmem_wr_en),
  .addr(cpu_dmem_addr),
  .wr_data(cpu_dmem_wr_data),
  .rd_data(uart_rd_data),
  .uart_rx(uart_rx),
  .uart_tx(uart_tx)
);

endmodule
