module fpga_top #(
  parameter HEARTBEAT_BIT = 23,
  parameter int CLK_HZ = 162_500_000,
  parameter int UART_BAUD = 115_200
)(
  input  wire        clk_100mhz,
  input  wire        clk_12mhz,
  input  logic       reset_n,


  inout  wire [1:0]  ddr3_dqs_n,
  inout  wire [15:0] ddr3_dq,
  inout  wire [1:0]  ddr3_dqs_p,

  output wire [13:0] ddr3_addr,
  output wire [2:0]  ddr3_ba,

  output wire        ddr3_ras_n,
  output wire        ddr3_cas_n,
  output wire        ddr3_we_n,
  output wire        ddr3_reset_n,

  output wire [0:0]  ddr3_ck_p,
  output wire [0:0]  ddr3_ck_n,
  output wire [0:0]  ddr3_cke,
  output wire [0:0]  ddr3_cs_n,

  output wire [1:0]  ddr3_dm,
  output wire [0:0]  ddr3_odt,

  input logic uart_rx,
  output logic uart_tx,
  output logic [3:0] led
);

logic [HEARTBEAT_BIT:0] heartbeat_counter;
logic [2:0]             mmio_led;

wire clk_ref_200mhz;
wire ref_clk_locked;

clk_wiz_0 u_clk_wiz_ref (
    .clk_in1  (clk_12mhz),
    .clk_out1 (clk_ref_200mhz),
    .reset    (1'b0),
    .locked   (ref_clk_locked)
);

(* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
logic [1:0] ref_locked_sync;

always_ff @(posedge clk_100mhz or negedge reset_n) begin

    if (!reset_n) begin
        ref_locked_sync <= 2'b00;
    end
    else begin
        ref_locked_sync[0] <= ref_clk_locked;
        ref_locked_sync[1] <= ref_locked_sync[0];
    end

end

wire mig_sys_rst_n;

assign mig_sys_rst_n = ref_locked_sync[1];

wire        ui_clk;
wire        ui_clk_sync_rst;
wire        init_calib_complete;
logic       soc_reset_request;
logic [1:0] soc_reset_sync;
logic       soc_reset_n;


// Command interface
logic [27:0] app_addr;
logic [2:0]  app_cmd;
logic        app_en;

wire         app_rdy;


// Write-data interface
logic [63:0] app_wdf_data;
logic        app_wdf_end;
logic [7:0]  app_wdf_mask;
logic        app_wdf_wren;

wire         app_wdf_rdy;


// Read-data interface
wire [63:0]  app_rd_data;
wire         app_rd_data_end;
wire         app_rd_data_valid;


// Other MIG signals
wire         app_sr_active;
wire         app_ref_ack;
wire         app_zq_ack;

wire [11:0]  device_temp;

assign soc_reset_request = !reset_n || ui_clk_sync_rst || !init_calib_complete;

always_ff @(posedge ui_clk or posedge soc_reset_request) begin
  if (soc_reset_request) begin
    soc_reset_sync <= 2'b00;
  end else begin
    soc_reset_sync <= {soc_reset_sync[0], 1'b1};
  end
end

assign soc_reset_n = soc_reset_sync[1];

always_ff @(posedge ui_clk or negedge soc_reset_n) begin
  if (!soc_reset_n) heartbeat_counter <= '0;
  else              heartbeat_counter <= heartbeat_counter + 1'b1;
end


// =========================================================
// 4. MIG instance
// =========================================================

mig_7series_0 u_mig (

    // -----------------------------------------------------
    // DDR3 physical pins
    // -----------------------------------------------------

    .ddr3_dq              (ddr3_dq),
    .ddr3_dqs_n           (ddr3_dqs_n),
    .ddr3_dqs_p           (ddr3_dqs_p),

    .ddr3_addr            (ddr3_addr),
    .ddr3_ba              (ddr3_ba),

    .ddr3_ras_n           (ddr3_ras_n),
    .ddr3_cas_n           (ddr3_cas_n),
    .ddr3_we_n            (ddr3_we_n),
    .ddr3_reset_n         (ddr3_reset_n),

    .ddr3_ck_p            (ddr3_ck_p),
    .ddr3_ck_n            (ddr3_ck_n),

    .ddr3_cke             (ddr3_cke),
    .ddr3_cs_n            (ddr3_cs_n),
    .ddr3_dm              (ddr3_dm),
    .ddr3_odt             (ddr3_odt),


    // -----------------------------------------------------
    // Clocks/reset
    // -----------------------------------------------------

    .sys_clk_i            (clk_100mhz),
    .clk_ref_i            (clk_ref_200mhz),
    .sys_rst              (mig_sys_rst_n),


    // -----------------------------------------------------
    // Command interface
    // -----------------------------------------------------

    .app_addr             (app_addr),
    .app_cmd              (app_cmd),
    .app_en               (app_en),
    .app_rdy              (app_rdy),


    // -----------------------------------------------------
    // Write-data interface
    // -----------------------------------------------------

    .app_wdf_data         (app_wdf_data),
    .app_wdf_end          (app_wdf_end),
    .app_wdf_mask         (app_wdf_mask),
    .app_wdf_wren         (app_wdf_wren),
    .app_wdf_rdy          (app_wdf_rdy),


    // -----------------------------------------------------
    // Read-data interface
    // -----------------------------------------------------

    .app_rd_data          (app_rd_data),
    .app_rd_data_end      (app_rd_data_end),
    .app_rd_data_valid    (app_rd_data_valid),


    // -----------------------------------------------------
    // Maintenance requests unused
    // -----------------------------------------------------

    .app_sr_req           (1'b0),
    .app_ref_req          (1'b0),
    .app_zq_req           (1'b0),

    .app_sr_active        (app_sr_active),
    .app_ref_ack          (app_ref_ack),
    .app_zq_ack           (app_zq_ack),


    // -----------------------------------------------------
    // MIG UI
    // -----------------------------------------------------

    .ui_clk               (ui_clk),
    .ui_clk_sync_rst      (ui_clk_sync_rst),

    .init_calib_complete  (init_calib_complete),
    .device_temp          (device_temp)
);


top #(
  .RESET_PC       (32'h0000),
  .RAM_BASE_ADDR  (32'h8000_0000),
  .RAM_ADDR_WIDTH (28),
  .LED_WIDTH      (3),
  .LED_BASE_ADDR  (32'h1000_0000),
  .UART_BASE_ADDR (32'h1000_0010),
  .CLK_HZ (CLK_HZ),
  .UART_BAUD(UART_BAUD)
) u_top (
  .clk      (ui_clk),
  .reset_n  (soc_reset_n),
  .mmio_led (mmio_led),
  .uart_rx (uart_rx),
  .uart_tx (uart_tx),
  .app_addr (app_addr),
  .app_cmd (app_cmd),
  .app_en (app_en),
  .app_rdy (app_rdy),
  .app_wdf_data (app_wdf_data),
  .app_wdf_end (app_wdf_end),
  .app_wdf_mask (app_wdf_mask),
  .app_wdf_wren (app_wdf_wren),
  .app_wdf_rdy (app_wdf_rdy),
  .app_rd_data (app_rd_data),
  .app_rd_data_end (app_rd_data_end),
  .app_rd_data_valid (app_rd_data_valid)
);

assign led[0]   = heartbeat_counter[HEARTBEAT_BIT];
assign led[3:1] = mmio_led;

endmodule
