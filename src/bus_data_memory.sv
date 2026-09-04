import risc_pkg::*;

module bus_data_memory #(
  parameter logic [31:0] RAM_BASE_ADDR = 32'h8000_0000,
  parameter RAM_ADDR_WIDTH = 6,
  parameter ROM_ADDR_WIDTH = 12,
  parameter LED_WIDTH = 3,
  parameter ROM_BASE_ADDR = 32'h0,
  parameter LED_BASE_ADDR = 32'h1000_0000,
  parameter UART_BASE_ADDR = 32'h1000_0010,
  parameter int CLK_HZ = 12_000_000,
  parameter int UART_BAUD = 115_200,
  parameter int RAM_STALL_CYCLES = 2
)(
  input  logic                 clk,
  input  logic                 reset_n,

  input  logic                 cpu_imem_req,
  input  logic [31:0]          cpu_imem_addr,
  output logic [31:0]          cpu_imem_data,
  output logic                 cpu_imem_ready,
  output logic                 cpu_imem_rd_data_valid,

  input  logic                 cpu_dmem_req,
  input  logic                 cpu_dmem_wr_en,
  input  mem_size_t            cpu_dmem_data_size,
  input  logic [31:0]          cpu_dmem_addr,
  input  logic [31:0]          cpu_dmem_wr_data,
  input  logic                 cpu_dmem_zero_extend,
  output logic [31:0]          cpu_dmem_rd_data,
  output logic                 cpu_dmem_ready,
  output logic                 cpu_dmem_rd_data_valid,

  output logic [LED_WIDTH-1:0] mmio_led,

  input  logic                 uart_rx,
  output logic                 uart_tx
);

logic dmem_ram_sel;
logic dmem_rom_sel;
logic dmem_led_sel;
logic dmem_uart_sel;
logic ram_req;
logic led_req;
logic uart_req;
logic rom_req;
logic dmem_ram_accept;
logic dmem_mmio_accept;
logic ram_busy;
logic uart_busy;
logic ram_selected_busy;
logic dmem_accept;

logic [31:0] ram_rd_data;
logic [31:0] led_rd_data;
logic [31:0] uart_rd_data;
logic [31:0] rom_rd_data;
logic [31:0] ram_offset_addr;
logic [31:0] imem_rom_offset_addr;
logic [31:0] dmem_rom_offset_addr;
logic imem_rom_sel;
logic imem_rom_wants;
logic dmem_rom_wants;

typedef enum logic [2:0] {
  DMEM_TARGET_NONE = 3'b000,
  DMEM_TARGET_RAM  = 3'b001,
  DMEM_TARGET_ROM  = 3'b010,
  DMEM_TARGET_LED  = 3'b011,
  DMEM_TARGET_UART = 3'b100
} dmem_target_t;

typedef enum logic [1:0] {
  RAM_IDLE = 2'b00,
  RAM_WAIT = 2'b01,
  RAM_DONE = 2'b11
} ram_state_t;

typedef enum logic [1:0] {
  MMIO_IDLE = 2'b00,
  MMIO_ISSUE = 2'b01,
  MMIO_WAIT = 2'b10,
  MMIO_DONE = 2'b11
} mmio_state_t;

typedef enum logic [1:0] {
  ROM_IDLE = 2'b00,
  ROM_WAIT = 2'b01,
  ROM_DONE = 2'b10
} rom_state_t;

typedef enum logic [1:0] {
  ROM_OWNER_NONE = 2'b00,
  ROM_OWNER_IMEM = 2'b01,
  ROM_OWNER_DMEM = 2'b10
} rom_owner_t;

dmem_target_t read_target_q;
dmem_target_t mmio_target_q;
dmem_target_t dmem_target;
dmem_target_t ram_active_target;
ram_state_t ram_state_q;
mmio_state_t mmio_state_q;
rom_state_t rom_state_q;
rom_owner_t rom_owner_q;
rom_owner_t rom_selected_owner;

logic        ram_txn_wr_en_q;
mem_size_t   ram_txn_data_size_q;
logic [31:0] ram_txn_addr_q;
logic [31:0] ram_txn_wr_data_q;
logic        ram_txn_zero_extend_q;

logic        ram_wr_en;
mem_size_t   ram_data_size;
logic [31:0] ram_addr;
logic [31:0] dmem_decoded_addr;
logic [31:0] ram_wr_data;
logic        ram_zero_extend;
logic        mmio_wr_en_q;
logic [31:0] mmio_addr_q;
logic [31:0] mmio_wr_data_q;
logic        rom_wr_en_q;
mem_size_t   rom_data_size_q;
logic [31:0] rom_addr_q;
logic        rom_zero_extend_q;
logic        rom_rr_q;

localparam logic [31:0] RAM_SIZE_BYTES = 32'h1 << RAM_ADDR_WIDTH;
localparam logic [31:0] ROM_SIZE_BYTES = 32'h1 << ROM_ADDR_WIDTH;

assign ram_offset_addr = cpu_dmem_addr - RAM_BASE_ADDR;
assign imem_rom_offset_addr = cpu_imem_addr - ROM_BASE_ADDR;
assign dmem_rom_offset_addr = cpu_dmem_addr - ROM_BASE_ADDR;
assign imem_rom_sel = (cpu_imem_addr >= ROM_BASE_ADDR) && (imem_rom_offset_addr < ROM_SIZE_BYTES);
assign dmem_rom_sel = (cpu_dmem_addr >= ROM_BASE_ADDR) && (dmem_rom_offset_addr < ROM_SIZE_BYTES);
assign imem_rom_wants = cpu_imem_req && imem_rom_sel;
assign dmem_rom_wants = cpu_dmem_req && dmem_rom_sel;
assign dmem_ram_sel = (cpu_dmem_addr >= RAM_BASE_ADDR) && (ram_offset_addr < RAM_SIZE_BYTES);
assign dmem_led_sel = (cpu_dmem_addr == LED_BASE_ADDR);
assign dmem_uart_sel = (cpu_dmem_addr[31:4] == UART_BASE_ADDR[31:4]);
always_comb begin
  unique case (dmem_target)
    DMEM_TARGET_RAM:  cpu_dmem_ready = (ram_state_q == RAM_IDLE);
    DMEM_TARGET_ROM:  cpu_dmem_ready = (rom_state_q == ROM_IDLE) &&
                                       (rom_selected_owner == ROM_OWNER_DMEM);
    DMEM_TARGET_LED,
    DMEM_TARGET_UART,
    DMEM_TARGET_NONE: cpu_dmem_ready = (mmio_state_q == MMIO_IDLE);
    default:         cpu_dmem_ready = 1'b0;
  endcase
end

assign dmem_accept = cpu_dmem_req && cpu_dmem_ready;
assign dmem_ram_accept = dmem_accept && (dmem_target == DMEM_TARGET_RAM);
assign dmem_mmio_accept = dmem_accept &&
                          (dmem_target != DMEM_TARGET_RAM) &&
                          (dmem_target != DMEM_TARGET_ROM);
assign ram_active_target = (ram_state_q == RAM_WAIT) ? read_target_q : dmem_target;
assign dmem_decoded_addr = (dmem_target == DMEM_TARGET_RAM) ? ram_offset_addr : cpu_dmem_addr;

assign ram_wr_en = (ram_state_q == RAM_WAIT) ? ram_txn_wr_en_q : cpu_dmem_wr_en;
assign ram_data_size = (ram_state_q == RAM_WAIT) ? ram_txn_data_size_q : cpu_dmem_data_size;
assign ram_addr = (ram_state_q == RAM_WAIT) ? ram_txn_addr_q : dmem_decoded_addr;
assign ram_wr_data = (ram_state_q == RAM_WAIT) ? ram_txn_wr_data_q : cpu_dmem_wr_data;
assign ram_zero_extend = (ram_state_q == RAM_WAIT) ? ram_txn_zero_extend_q : cpu_dmem_zero_extend;

always_comb begin
  unique case (1'b1)
    dmem_ram_sel: dmem_target = DMEM_TARGET_RAM;
    dmem_rom_sel: dmem_target = DMEM_TARGET_ROM;
    dmem_led_sel: dmem_target = DMEM_TARGET_LED;
    dmem_uart_sel: dmem_target = DMEM_TARGET_UART;
    default: dmem_target = DMEM_TARGET_NONE;
  endcase
end

always_comb begin
  rom_selected_owner = ROM_OWNER_NONE;

  if (rom_state_q == ROM_IDLE) begin
    unique case ({imem_rom_wants, dmem_rom_wants})
      2'b10: rom_selected_owner = ROM_OWNER_IMEM;
      2'b01: rom_selected_owner = ROM_OWNER_DMEM;
      2'b11: rom_selected_owner = rom_rr_q ? ROM_OWNER_DMEM : ROM_OWNER_IMEM;
      default: rom_selected_owner = ROM_OWNER_NONE;
    endcase
  end
end

always_comb begin
  unique case (ram_active_target)
    DMEM_TARGET_RAM:  ram_selected_busy = ram_busy;
    DMEM_TARGET_LED:  ram_selected_busy = 1'b0;
    DMEM_TARGET_UART: ram_selected_busy = uart_busy;
    default:          ram_selected_busy = 1'b0;
  endcase
end

assign cpu_dmem_rd_data_valid = (ram_state_q == RAM_DONE) ||
                                (mmio_state_q == MMIO_DONE) ||
                                ((rom_state_q == ROM_DONE) &&
                                 (rom_owner_q == ROM_OWNER_DMEM));
assign cpu_imem_ready = imem_rom_sel &&
                        (rom_state_q == ROM_IDLE) &&
                        (rom_selected_owner == ROM_OWNER_IMEM);
assign cpu_imem_rd_data_valid = (rom_state_q == ROM_DONE) &&
                                (rom_owner_q == ROM_OWNER_IMEM);
assign cpu_imem_data = rom_rd_data;

always_comb begin
  ram_req = dmem_ram_accept;
  led_req = (mmio_state_q == MMIO_ISSUE) && (mmio_target_q == DMEM_TARGET_LED);
  uart_req = (mmio_state_q == MMIO_ISSUE) && (mmio_target_q == DMEM_TARGET_UART);
  rom_req = (rom_state_q == ROM_WAIT) && !rom_wr_en_q;
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    read_target_q <= DMEM_TARGET_NONE;
    mmio_target_q <= DMEM_TARGET_NONE;
    ram_state_q <= RAM_IDLE;
    mmio_state_q <= MMIO_IDLE;
    rom_state_q <= ROM_IDLE;
    rom_owner_q <= ROM_OWNER_NONE;
    ram_txn_wr_en_q <= 1'b0;
    ram_txn_data_size_q <= WORD;
    ram_txn_addr_q <= 32'h0;
    ram_txn_wr_data_q <= 32'h0;
    ram_txn_zero_extend_q <= 1'b0;
    mmio_wr_en_q <= 1'b0;
    mmio_addr_q <= 32'h0;
    mmio_wr_data_q <= 32'h0;
    rom_wr_en_q <= 1'b0;
    rom_data_size_q <= WORD;
    rom_addr_q <= 32'h0;
    rom_zero_extend_q <= 1'b0;
    rom_rr_q <= 1'b0;
  end else begin
    if (dmem_mmio_accept) begin
      mmio_target_q <= dmem_target;
      mmio_wr_en_q <= cpu_dmem_wr_en;
      mmio_addr_q <= cpu_dmem_addr;
      mmio_wr_data_q <= cpu_dmem_wr_data;
      mmio_state_q <= MMIO_ISSUE;
    end else begin
      unique case (mmio_state_q)
        MMIO_IDLE: begin
        end

        MMIO_ISSUE: begin
          mmio_state_q <= MMIO_WAIT;
        end

        MMIO_WAIT: begin
          if (!uart_busy) begin
            mmio_state_q <= MMIO_DONE;
          end
        end

        MMIO_DONE: begin
          mmio_state_q <= MMIO_IDLE;
        end
      endcase
    end

    unique case (ram_state_q)
      RAM_IDLE: begin
        if (dmem_ram_accept) begin
          read_target_q <= dmem_target;
          ram_txn_wr_en_q <= cpu_dmem_wr_en;
          ram_txn_data_size_q <= cpu_dmem_data_size;
          ram_txn_addr_q <= dmem_decoded_addr;
          ram_txn_wr_data_q <= cpu_dmem_wr_data;
          ram_txn_zero_extend_q <= cpu_dmem_zero_extend;

          ram_state_q <= RAM_WAIT;
        end
      end

      RAM_WAIT: begin
        if (!ram_selected_busy) begin
          ram_state_q <= RAM_DONE;
        end
      end

      RAM_DONE: begin
        ram_state_q <= RAM_IDLE;
      end
    endcase

    unique case (rom_state_q)
      ROM_IDLE: begin
        if (rom_selected_owner == ROM_OWNER_IMEM) begin
          rom_owner_q <= ROM_OWNER_IMEM;
          rom_wr_en_q <= 1'b0;
          rom_data_size_q <= WORD;
          rom_addr_q <= imem_rom_offset_addr;
          rom_zero_extend_q <= 1'b0;
          rom_rr_q <= 1'b1;
          rom_state_q <= ROM_WAIT;
        end else if (rom_selected_owner == ROM_OWNER_DMEM) begin
          rom_owner_q <= ROM_OWNER_DMEM;
          rom_wr_en_q <= cpu_dmem_wr_en;
          rom_data_size_q <= cpu_dmem_data_size;
          rom_addr_q <= dmem_rom_offset_addr;
          rom_zero_extend_q <= cpu_dmem_zero_extend;
          rom_rr_q <= 1'b0;
          rom_state_q <= cpu_dmem_wr_en ? ROM_DONE : ROM_WAIT;
        end
      end

      ROM_WAIT: begin
        rom_state_q <= ROM_DONE;
      end

      ROM_DONE: begin
        rom_state_q <= ROM_IDLE;
      end
    endcase
  end
end

always_comb begin
  if ((rom_state_q == ROM_DONE) && (rom_owner_q == ROM_OWNER_DMEM)) begin
    cpu_dmem_rd_data = rom_wr_en_q ? 32'h0 : rom_rd_data;
  end else begin
    unique case ((mmio_state_q == MMIO_DONE) ? mmio_target_q : read_target_q)
      DMEM_TARGET_RAM:  cpu_dmem_rd_data = ram_rd_data;
      DMEM_TARGET_LED:  cpu_dmem_rd_data = led_rd_data;
      DMEM_TARGET_UART: cpu_dmem_rd_data = uart_rd_data;
      default:          cpu_dmem_rd_data = 32'h0;
    endcase
  end
end

data_memory #(
  .ADDR_WIDTH(RAM_ADDR_WIDTH),
  .STALL_CYCLES(RAM_STALL_CYCLES)
) u_data_memory (
  .clk              (clk),
  .reset_n          (reset_n),
  .dmem_req         (ram_req),
  .dmem_wr_en       (ram_wr_en),
  .dmem_data_size   (ram_data_size),
  .dmem_addr        (ram_addr),
  .dmem_wr_data     (ram_wr_data),
  .dmem_zero_extend (ram_zero_extend),
  .dmem_rd_data     (ram_rd_data),
  .dmem_busy        (ram_busy)
);

mmio_led #(
  .LED_WIDTH(LED_WIDTH)
) u_mmio_led (
  .clk     (clk),
  .reset_n (reset_n),
  .req     (led_req),
  .wr_en   (mmio_wr_en_q),
  .wr_data (mmio_wr_data_q),
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
  .wr_en(mmio_wr_en_q),
  .addr(mmio_addr_q),
  .wr_data(mmio_wr_data_q),
  .rd_data(uart_rd_data),
  .busy(uart_busy),
  .uart_rx(uart_rx),
  .uart_tx(uart_tx)
);

rom_memory #(
  .ADDR_WIDTH(ROM_ADDR_WIDTH)
) u_rom_memory (
  .clk         (clk),
  .req         (rom_req),
  .data_size   (rom_data_size_q),
  .addr        (rom_addr_q),
  .zero_extend (rom_zero_extend_q),
  .rd_data     (rom_rd_data)
);

endmodule
