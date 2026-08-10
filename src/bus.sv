import risc_pkg::*;

module bus #(
  parameter RAM_ADDR_WIDTH = 6,
  parameter LED_WIDTH = 3,
  parameter LED_BASE_ADDR = 32'h1000_0000,
  parameter UART_BASE_ADDR = 32'h1000_0010,
  parameter int CLK_HZ = 12_000_000,
  parameter int UART_BAUD = 115_200,
  parameter int RAM_STALL_CYCLES = 2
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
  output logic                 cpu_dmem_busy,

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
logic ram_busy;
logic selected_busy;
logic accept_txn;

logic [31:0] ram_rd_data;
logic [31:0] led_rd_data;
logic [31:0] uart_rd_data;

typedef enum logic [1:0] {
  BUS_TARGET_NONE = 2'b00,
  BUS_TARGET_RAM  = 2'b01,
  BUS_TARGET_LED  = 2'b10,
  BUS_TARGET_UART = 2'b11
} bus_target_t;

typedef enum logic [1:0] { 
  BUS_IDLE = 2'b00,
  BUS_WAIT = 2'b01,
  BUS_DONE = 2'b11
} bus_state_t;

bus_state_t bus_state_q;
bus_target_t read_target_q;
bus_target_t decoded_target;
bus_target_t active_target;

logic        txn_wr_en;
mem_size_t   txn_data_size;
logic [31:0] txn_addr;
logic [31:0] txn_wr_data;
logic        txn_zero_extend;

logic        bus_wr_en;
mem_size_t   bus_data_size;
logic [31:0] bus_addr;
logic [31:0] bus_wr_data;
logic        bus_zero_extend;


assign ram_sel = (cpu_dmem_addr[31:RAM_ADDR_WIDTH] == '0);
assign led_sel = (cpu_dmem_addr == LED_BASE_ADDR);
assign uart_sel = (cpu_dmem_addr[31:4] == UART_BASE_ADDR[31:4]);
assign accept_txn = (bus_state_q == BUS_IDLE) && cpu_dmem_req;
assign active_target = (bus_state_q == BUS_WAIT) ? read_target_q : decoded_target;

assign bus_wr_en = (bus_state_q == BUS_WAIT) ? txn_wr_en : cpu_dmem_wr_en;
assign bus_data_size = (bus_state_q == BUS_WAIT) ? txn_data_size : cpu_dmem_data_size;
assign bus_addr = (bus_state_q == BUS_WAIT) ? txn_addr : cpu_dmem_addr;
assign bus_wr_data = (bus_state_q == BUS_WAIT) ? txn_wr_data : cpu_dmem_wr_data;
assign bus_zero_extend = (bus_state_q == BUS_WAIT) ? txn_zero_extend : cpu_dmem_zero_extend;

always_comb begin
  unique case (1'b1)
    ram_sel: begin
      decoded_target = BUS_TARGET_RAM;
    end
    led_sel: begin
      decoded_target = BUS_TARGET_LED;
    end
    uart_sel: begin
      decoded_target = BUS_TARGET_UART;
    end
    default: begin
      decoded_target = BUS_TARGET_NONE;
    end
  endcase
end

always_comb begin
  unique case (active_target)
    BUS_TARGET_RAM:  selected_busy = ram_busy;
    BUS_TARGET_LED:  selected_busy = 1'b0;
    BUS_TARGET_UART: selected_busy = 1'b0;
    default:         selected_busy = 1'b0;
  endcase
end

assign cpu_dmem_busy = (bus_state_q == BUS_WAIT) || (accept_txn && selected_busy);

always_comb begin
  ram_req = 1'b0;
  led_req = 1'b0;
  uart_req = 1'b0;
  if (accept_txn) begin
    unique case (decoded_target)
      BUS_TARGET_RAM:  ram_req = 1'b1;
      BUS_TARGET_LED:  led_req = 1'b1;
      BUS_TARGET_UART: uart_req = 1'b1;
      default: begin
      end
    endcase
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    read_target_q <= BUS_TARGET_NONE;
    bus_state_q <= BUS_IDLE;
    txn_wr_en <= 1'b0;
    txn_data_size <= WORD;
    txn_addr <= 32'h0;
    txn_wr_data <= 32'h0;
    txn_zero_extend <= 1'b0;
  end else begin
    unique case (bus_state_q)
      BUS_IDLE: begin
        if (cpu_dmem_req) begin
          read_target_q <= decoded_target;
          txn_wr_en <= cpu_dmem_wr_en;
          txn_data_size <= cpu_dmem_data_size;
          txn_addr <= cpu_dmem_addr;
          txn_wr_data <= cpu_dmem_wr_data;
          txn_zero_extend <= cpu_dmem_zero_extend;
          
          if (selected_busy) begin
            bus_state_q <= BUS_WAIT;
          end
        end
      end
      BUS_WAIT: begin
        if(!selected_busy) begin
          bus_state_q <= BUS_DONE;
        end
      end
      BUS_DONE: begin
        bus_state_q <= BUS_IDLE;
      end
    endcase
  end
end

always_comb begin
  unique case (read_target_q)
    BUS_TARGET_RAM:  cpu_dmem_rd_data = ram_rd_data;
    BUS_TARGET_LED:  cpu_dmem_rd_data = led_rd_data;
    BUS_TARGET_UART: cpu_dmem_rd_data = uart_rd_data;
    default:         cpu_dmem_rd_data = 32'h0;
  endcase
end

data_memory #(
  .ADDR_WIDTH(RAM_ADDR_WIDTH),
  .STALL_CYCLES(RAM_STALL_CYCLES)
) u_data_memory (
  .clk              (clk),
  .reset_n          (reset_n),
  .dmem_req         (ram_req),
  .dmem_wr_en       (bus_wr_en),
  .dmem_data_size   (bus_data_size),
  .dmem_addr        (bus_addr),
  .dmem_wr_data     (bus_wr_data),
  .dmem_zero_extend (bus_zero_extend),
  .dmem_rd_data     (ram_rd_data),
  .dmem_busy        (ram_busy)
);

mmio_led #(
  .LED_WIDTH(LED_WIDTH)
) u_mmio_led (
  .clk     (clk),
  .reset_n (reset_n),
  .req     (led_req),
  .wr_en   (bus_wr_en),
  .wr_data (bus_wr_data),
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
  .wr_en(bus_wr_en),
  .addr(bus_addr),
  .wr_data(bus_wr_data),
  .rd_data(uart_rd_data),
  .uart_rx(uart_rx),
  .uart_tx(uart_tx)
);

endmodule
