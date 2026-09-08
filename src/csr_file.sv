import risc_pkg::*;

module csr_file (
  input  logic        clk,
  input  logic        reset_n,

  input  logic [11:0] rd_addr,
  output logic [31:0] rd_data,

  input  logic        wr_en,
  input  logic [11:0] wr_addr,
  input  logic [31:0] wr_data,

  input  logic        instret_inc,

  input  logic        trap_enter,
  input  trap_payload_t trap,
  input  logic        mret_enter,

  output logic [31:0] mtvec,
  output logic [31:0] mepc
);

localparam logic [11:0] CSR_MSTATUS  = 12'h300;
localparam logic [11:0] CSR_MIE      = 12'h304;
localparam logic [11:0] CSR_MTVEC    = 12'h305;
localparam logic [11:0] CSR_MSCRATCH = 12'h340;
localparam logic [11:0] CSR_MEPC     = 12'h341;
localparam logic [11:0] CSR_MCAUSE   = 12'h342;
localparam logic [11:0] CSR_MTVAL    = 12'h343;
localparam logic [11:0] CSR_MIP      = 12'h344;
localparam logic [11:0] CSR_MCYCLE   = 12'hb00;
localparam logic [11:0] CSR_MINSTRET = 12'hb02;

localparam int MSTATUS_MIE_BIT = 3;
localparam int MSTATUS_MPIE_BIT = 7;
localparam int MSTATUS_MPP_LSB = 11;
localparam int MSTATUS_MPP_MSB = 12;
localparam logic [1:0] PRIV_M = 2'b11;

logic [31:0] mstatus_q;
logic [31:0] mie_q;
logic [31:0] mtvec_q;
logic [31:0] mscratch_q;
logic [31:0] mepc_q;
logic [31:0] mcause_q;
logic [31:0] mtval_q;
logic [31:0] mip_q;
logic [31:0] mcycle_q;
logic [31:0] minstret_q;

assign mtvec = mtvec_q;
assign mepc = mepc_q;

always_comb begin
  unique case (rd_addr)
    CSR_MSTATUS:  rd_data = mstatus_q;
    CSR_MIE:      rd_data = mie_q;
    CSR_MTVEC:    rd_data = mtvec_q;
    CSR_MSCRATCH: rd_data = mscratch_q;
    CSR_MEPC:     rd_data = mepc_q;
    CSR_MCAUSE:   rd_data = mcause_q;
    CSR_MTVAL:    rd_data = mtval_q;
    CSR_MIP:      rd_data = mip_q;
    CSR_MCYCLE:   rd_data = mcycle_q;
    CSR_MINSTRET: rd_data = minstret_q;
    default:      rd_data = 32'h0;
  endcase

  if (wr_en && (wr_addr == rd_addr)) begin
    rd_data = wr_data;
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    mstatus_q <= 32'h0;
    mie_q <= 32'h0;
    mtvec_q <= 32'h0;
    mscratch_q <= 32'h0;
    mepc_q <= 32'h0;
    mcause_q <= 32'h0;
    mtval_q <= 32'h0;
    mip_q <= 32'h0;
    mcycle_q <= 32'h0;
    minstret_q <= 32'h0;
  end else begin
    mcycle_q <= mcycle_q + 1'b1;

    if (instret_inc) begin
      minstret_q <= minstret_q + 1'b1;
    end

    if (trap_enter) begin
      mepc_q <= trap.mepc;
      mcause_q <= trap.mcause;
      mtval_q <= trap.mtval;
      mstatus_q[MSTATUS_MPIE_BIT] <= mstatus_q[MSTATUS_MIE_BIT];
      mstatus_q[MSTATUS_MIE_BIT] <= 1'b0;
      mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRIV_M;
    end else if (mret_enter) begin
      mstatus_q[MSTATUS_MIE_BIT] <= mstatus_q[MSTATUS_MPIE_BIT];
      mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
      mstatus_q[MSTATUS_MPP_MSB:MSTATUS_MPP_LSB] <= PRIV_M;
    end else if (wr_en) begin
      unique case (wr_addr)
        CSR_MSTATUS:  mstatus_q <= wr_data;
        CSR_MIE:      mie_q <= wr_data;
        CSR_MTVEC:    mtvec_q <= wr_data;
        CSR_MSCRATCH: mscratch_q <= wr_data;
        CSR_MEPC:     mepc_q <= wr_data;
        CSR_MCAUSE:   mcause_q <= wr_data;
        CSR_MTVAL:    mtval_q <= wr_data;
        CSR_MIP:      mip_q <= wr_data;
        CSR_MCYCLE:   mcycle_q <= wr_data;
        CSR_MINSTRET: minstret_q <= wr_data;
        default: begin
        end
      endcase
    end
  end
end

endmodule
