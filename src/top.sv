import risc_pkg::*;

module top #(
  parameter RESET_PC = 32'h0000,
  parameter logic [31:0] RAM_BASE_ADDR = 32'h8000_0000,
  parameter int RAM_ADDR_WIDTH = 28,
  parameter ROM_ADDR_WIDTH = 12,
  parameter LED_WIDTH = 3,
  parameter ROM_BASE_ADDR = 32'h0,
  parameter CLINT_BASE_ADDR = 32'h0200_0000,
  parameter LED_BASE_ADDR = 32'h1000_0000,
  parameter UART_BASE_ADDR = 32'h1000_0010,
  parameter int CLK_HZ = 12_000_000,
  parameter int UART_BAUD = 115_200
)(
  input  logic                 clk,
  input  logic                 reset_n,
  input  logic                 ui_clk,
  input  logic                 ui_reset_n,
  output logic [LED_WIDTH-1:0] mmio_led,
  input  logic                 uart_rx,
  output logic                 uart_tx,

  output logic [27:0]          app_addr,
  output logic [2:0]           app_cmd,
  output logic                 app_en,
  input  logic                 app_rdy,

  output logic [63:0]          app_wdf_data,
  output logic                 app_wdf_end,
  output logic [7:0]           app_wdf_mask,
  output logic                 app_wdf_wren,
  input  logic                 app_wdf_rdy,

  input  logic [63:0]          app_rd_data,
  input  logic                 app_rd_data_end,
  input  logic                 app_rd_data_valid
);

logic        cpu_imem_req;
logic [31:0] cpu_imem_addr;
logic [31:0] cpu_imem_data;
logic        cpu_imem_ready;
logic        cpu_imem_rd_data_valid;

logic        cpu_dmem_req;
logic        cpu_dmem_wr_en;
mem_size_t   cpu_dmem_data_size;
logic [31:0] cpu_dmem_addr;
logic [31:0] cpu_dmem_wr_data;
logic        cpu_dmem_zero_extend;
logic [31:0] cpu_dmem_rd_data;
logic        cpu_dmem_ready;
logic        cpu_dmem_rd_data_valid;
logic        clint_msip;
logic        clint_mtip;
logic [31:0] irq_pending;

always_comb begin
  irq_pending = 32'h0;
  irq_pending[IRQ_CAUSE_MSI] = clint_msip;
  irq_pending[IRQ_CAUSE_MTI] = clint_mtip;
end

cpu #(
  .RESET_PC(RESET_PC)
) u_cpu (
  .clk                 (clk),
  .reset_n             (reset_n),
  .irq_pending         (irq_pending),
  .imem_req            (cpu_imem_req),
  .imem_addr           (cpu_imem_addr),
  .imem_data           (cpu_imem_data),
  .imem_ready          (cpu_imem_ready),
  .imem_rd_data_valid  (cpu_imem_rd_data_valid),
  .dmem_req            (cpu_dmem_req),
  .dmem_wr_en          (cpu_dmem_wr_en),
  .dmem_data_size      (cpu_dmem_data_size),
  .dmem_addr           (cpu_dmem_addr),
  .dmem_wr_data        (cpu_dmem_wr_data),
  .dmem_zero_extend    (cpu_dmem_zero_extend),
  .dmem_rd_data        (cpu_dmem_rd_data),
  .dmem_ready          (cpu_dmem_ready),
  .dmem_rd_data_valid  (cpu_dmem_rd_data_valid)
);

bus #(
  .RAM_BASE_ADDR  (RAM_BASE_ADDR),
  .RAM_ADDR_WIDTH (RAM_ADDR_WIDTH),
  .ROM_ADDR_WIDTH (ROM_ADDR_WIDTH),
  .LED_WIDTH      (LED_WIDTH),
  .ROM_BASE_ADDR  (ROM_BASE_ADDR),
  .CLINT_BASE_ADDR(CLINT_BASE_ADDR),
  .LED_BASE_ADDR  (LED_BASE_ADDR),
  .UART_BASE_ADDR (UART_BASE_ADDR),
  .CLK_HZ         (CLK_HZ),
  .UART_BAUD      (UART_BAUD)
) u_bus (
  .clk                   (clk),
  .reset_n               (reset_n),
  .ui_clk                (ui_clk),
  .ui_reset_n            (ui_reset_n),
  .cpu_imem_req          (cpu_imem_req),
  .cpu_imem_addr         (cpu_imem_addr),
  .cpu_imem_data         (cpu_imem_data),
  .cpu_imem_ready        (cpu_imem_ready),
  .cpu_imem_rd_data_valid(cpu_imem_rd_data_valid),
  .cpu_dmem_req          (cpu_dmem_req),
  .cpu_dmem_wr_en        (cpu_dmem_wr_en),
  .cpu_dmem_data_size    (cpu_dmem_data_size),
  .cpu_dmem_addr         (cpu_dmem_addr),
  .cpu_dmem_wr_data      (cpu_dmem_wr_data),
  .cpu_dmem_zero_extend  (cpu_dmem_zero_extend),
  .cpu_dmem_rd_data      (cpu_dmem_rd_data),
  .cpu_dmem_ready        (cpu_dmem_ready),
  .cpu_dmem_rd_data_valid(cpu_dmem_rd_data_valid),
  .mmio_led              (mmio_led),
  .clint_msip            (clint_msip),
  .clint_mtip            (clint_mtip),
  .uart_rx               (uart_rx),
  .uart_tx               (uart_tx),
  .app_addr              (app_addr),
  .app_cmd               (app_cmd),
  .app_en                (app_en),
  .app_rdy               (app_rdy),
  .app_wdf_data          (app_wdf_data),
  .app_wdf_end           (app_wdf_end),
  .app_wdf_mask          (app_wdf_mask),
  .app_wdf_wren          (app_wdf_wren),
  .app_wdf_rdy           (app_wdf_rdy),
  .app_rd_data           (app_rd_data),
  .app_rd_data_end       (app_rd_data_end),
  .app_rd_data_valid     (app_rd_data_valid)
);

endmodule
