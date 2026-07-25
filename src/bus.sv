import risc_pkg::*;

module bus #(
  parameter RAM_ADDR_WIDTH = 6,
  parameter LED_WIDTH = 3,
  parameter LED_BASE_ADDR = 32'h1000_0000
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

  output logic [LED_WIDTH-1:0] mmio_led
);

logic ram_sel;
logic led_sel;
logic ram_req;
logic led_req;

logic [31:0] ram_rd_data;
logic [31:0] led_rd_data;

typedef enum logic [1:0] {
  READ_TARGET_NONE = 2'b00,
  READ_TARGET_RAM  = 2'b01,
  READ_TARGET_LED  = 2'b10
} read_target_t;

read_target_t read_target_q;

assign ram_sel = (cpu_dmem_addr[31:RAM_ADDR_WIDTH] == '0);
assign led_sel = (cpu_dmem_addr == LED_BASE_ADDR);

always_comb begin
  ram_req = 1'b0;
  led_req = 1'b0;

  unique case (1'b1)
    ram_sel: ram_req = cpu_dmem_req;
    led_sel: led_req = cpu_dmem_req;
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
      default: read_target_q <= READ_TARGET_NONE;
    endcase
  end
end

always_comb begin
  unique case (read_target_q)
    READ_TARGET_RAM:  cpu_dmem_rd_data = ram_rd_data;
    READ_TARGET_LED:  cpu_dmem_rd_data = led_rd_data;
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

endmodule
