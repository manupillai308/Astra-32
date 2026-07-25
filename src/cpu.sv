// --------------------------------------------------------
// RISC-V CPU Core (5-stage, serialized)
//
//  Stages:  IF  ->  ID  ->  EX  ->  MEM  ->  WB
//  Boundaries: { sync imem + pc_pipe } | id_ex | ex_mem | mem_wb
//
//  This is a *structural* pipeline only:
//    fetch_enable is asserted only when the front-half of the
//    pipe (if_id, id_ex, ex_mem) is empty, so at most one
//    real instruction is in flight at a time. That makes the
//    design hazard-free by construction — no forwarding,
//    no stall, no flush needed. ~5 cycles per instruction.
//    Hazard logic will replace serialization in §1.4.
//
//  Memories (imem, dmem) are synchronous-read so they map to
//  FPGA BRAM. The 1-cycle BRAM latency is absorbed by the
//  pipeline register at each end.
// --------------------------------------------------------
import risc_pkg::*;

module cpu #(
  parameter RESET_PC = 32'h0000
)(
  input logic clk,
  input logic reset_n,

  output logic        dmem_req,
  output logic        dmem_wr_en,
  output mem_size_t   dmem_data_size,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wr_data,
  output logic        dmem_zero_extend,
  input  logic [31:0] dmem_rd_data
);

// =====================================================
// IF stage
// =====================================================
logic [31:0] pc;
logic        fetch_enable;
logic        load_use_stall;
logic        branch_redirect;
logic [31:0] redirect_target;

logic        imem_req;
logic [31:0] imem_addr;
logic [31:0] imem_data;

// IF/ID equivalent: pc piped one cycle to align with the
// sync imem output reg, which acts as IF/ID.instruction.
logic        if_id_valid;
logic [31:0] if_id_pc;

// =====================================================
// Pipeline registers
// =====================================================
id_ex_t  id_ex;
ex_mem_t ex_mem;
mem_wb_t mem_wb;

// =====================================================
// ID stage combinational outputs (decode + control + regfile read)
// =====================================================
logic [4:0]  id_rs1_addr, id_rs2_addr, id_rd_addr;
logic [6:0]  id_opcode;
logic [2:0]  id_funct3;
logic [6:0]  id_funct7;
logic        id_r_type, id_i_type, id_s_type, id_b_type, id_u_type, id_j_type;
logic [31:0] id_immediate;

logic [31:0] id_rs1_data, id_rs2_data;

logic        id_pc_sel, id_op1_sel, id_op2_sel;
alu_op_t     id_alu_op;
wb_src_t     id_rf_wr_data_sel;
logic        id_dmem_req, id_dmem_wr_en, id_dmem_zero_extend;
mem_size_t   id_dmem_size;
logic        id_rf_wr_en;

// =====================================================
// EX stage signals
// =====================================================
logic [31:0] ex_alu_a, ex_alu_b, ex_alu_res;
logic        ex_branch_taken;
logic [31:0] ex_branch_target;
logic [31:0] ex_next_seq_pc;

// =====================================================
// MEM / WB
// =====================================================
logic [31:0] wb_data;

logic forward_a_from_ex_mem;
logic forward_b_from_ex_mem;

logic forward_a_from_mem_wb;
logic forward_b_from_mem_wb;


logic [31:0] rs1_data_resolved;
logic [31:0] rs2_data_resolved;
// --------------------------------------------------------
// Fetch gate
//   Empty front-half => safe to fetch. mem_wb.valid is NOT
//   in the mask: WB has no effect on the address stream,
//   and the regfile write at end of WB lands BEFORE the
//   next instruction's ID-stage regfile read.
// --------------------------------------------------------
assign fetch_enable = !load_use_stall;

// --------------------------------------------------------
// Branch / jump redirect
//   Decided in EX, observed via EX/MEM register.
// --------------------------------------------------------
assign branch_redirect = ex_mem.valid && (ex_mem.branch_taken || ex_mem.pc_sel);
assign redirect_target = ex_mem.branch_target;

// --------------------------------------------------------
// PC register
//   Priority: redirect (overrides any prediction) > fetch (+4).
//   Otherwise hold.
// --------------------------------------------------------
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n)               pc <= RESET_PC;
  else if (branch_redirect)   pc <= redirect_target;
  else if (fetch_enable)      pc <= pc + 32'd4;
end

// --------------------------------------------------------
// IF/ID boundary
//   imem_req gates the BRAM read so imem_data is preserved
//   across the cycles where the pipe is busy. pc_pipe carries
//   the pc of the instruction whose word is arriving next cycle.
// --------------------------------------------------------
assign imem_req  = fetch_enable;
assign imem_addr = pc;

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    if_id_valid <= 1'b0;
    if_id_pc    <= RESET_PC;
  end else if (branch_redirect) begin
    // Defensive: squash any speculative fetch behind the branch.
    // CONTROL HAZARD: IF/ID flush
    if_id_valid <= 1'b0;
  end else if (load_use_stall) begin
    // hold PC and IF/ID
  end else begin
    if_id_valid <= fetch_enable;
    if_id_pc    <= pc;
  end
end

// --------------------------------------------------------
// IMEM
// --------------------------------------------------------
instruction_memory u_instruction_memory (
  .clk       (clk),
  .imem_req  (imem_req),
  .imem_addr (imem_addr),
  .imem_data (imem_data)
);

// --------------------------------------------------------
// ID stage : decode + control + regfile read
//   Consumes (if_id_valid, if_id_pc, imem_data). Outputs are
//   combinational and feed the ID/EX register.
// --------------------------------------------------------
decode u_decode (
    .instruction (imem_data),
    .rs1_addr    (id_rs1_addr),
    .rs2_addr    (id_rs2_addr),
    .rd_addr     (id_rd_addr),
    .opcode      (id_opcode),
    .funct3      (id_funct3),
    .funct7      (id_funct7),
    .r_type      (id_r_type),
    .i_type      (id_i_type),
    .s_type      (id_s_type),
    .b_type      (id_b_type),
    .u_type      (id_u_type),
    .j_type      (id_j_type),
    .immediate   (id_immediate)
);

control u_control (
    .r_type           (id_r_type),
    .i_type           (id_i_type),
    .s_type           (id_s_type),
    .b_type           (id_b_type),
    .u_type           (id_u_type),
    .j_type           (id_j_type),
    .funct3           (id_funct3),
    .funct7           (id_funct7),
    .opcode           (id_opcode),

    .pc_sel           (id_pc_sel),
    .op1_sel          (id_op1_sel),
    .op2_sel          (id_op2_sel),
    .alu_op           (id_alu_op),
    .rf_wr_data_sel   (id_rf_wr_data_sel),
    .dmem_req         (id_dmem_req),
    .dmem_size        (id_dmem_size),
    .dmem_wr_en       (id_dmem_wr_en),
    .dmem_zero_extend (id_dmem_zero_extend),
    .rf_wr_en         (id_rf_wr_en)
);

// Regfile: combinational read in ID, sync write from WB.
// Write enable is gated by mem_wb.valid so bubbles don't write.
register_file u_register_file (
    .clk      (clk),
    .reset_n  (reset_n),
    .rs1_addr (id_rs1_addr),
    .rs2_addr (id_rs2_addr),
    .rd_addr  (mem_wb.rd_addr),
    .rf_wr_en (mem_wb.valid && mem_wb.rf_wr_en),
    .wr_data  (wb_data),
    .rs1_data (id_rs1_data),
    .rs2_data (id_rs2_data)
);

// --------------------------------------------------------
// ID / EX  register
// --------------------------------------------------------
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n || load_use_stall) id_ex <= '0;
  else begin
    id_ex.valid            <= if_id_valid && !branch_redirect; // CONTROL HAZARD: ID/EX flush
    id_ex.pc               <= if_id_pc;
    id_ex.rs1_addr         <= id_rs1_addr;
    id_ex.rs2_addr         <= id_rs2_addr;
    id_ex.rs1_data         <= id_rs1_data;
    id_ex.rs2_data         <= id_rs2_data;
    id_ex.immediate        <= id_immediate;
    id_ex.rd_addr          <= id_rd_addr;
    id_ex.op1_sel          <= id_op1_sel;
    id_ex.op2_sel          <= id_op2_sel;
    id_ex.alu_op           <= id_alu_op;
    id_ex.is_b_type        <= id_b_type;
    id_ex.funct3           <= id_funct3;
    id_ex.pc_sel           <= id_pc_sel;
    id_ex.dmem_req         <= id_dmem_req;
    id_ex.dmem_wr_en       <= id_dmem_wr_en;
    id_ex.dmem_size        <= id_dmem_size;
    id_ex.dmem_zero_extend <= id_dmem_zero_extend;
    id_ex.rf_wr_en         <= id_rf_wr_en;
    id_ex.rf_wr_data_sel   <= id_rf_wr_data_sel;
  end
end

// --------------------------------------------------------
// EX stage : ALU + branch eval + branch target
//   branch_target uses ALU output ({alu_res[31:1],1'b0}) which
//   for B-type/JAL is pc+imm and for JALR is rs1+imm (both
//   already routed through the ALU by control_t settings).
// --------------------------------------------------------
// LOAD USE HAZARD: stall
// N:   lw   x5, 0(x0)
// N+1: addi x6, x5, 3
assign load_use_stall = id_ex.valid && id_ex.dmem_req && !id_ex.dmem_wr_en // id_ex is a load
                        && (id_ex.rd_addr == id_rs1_addr || id_ex.rd_addr == id_rs2_addr) 
                        && (id_ex.rd_addr != 0);
// DATA HAZARD (RAW): forwarding
// N:   addi x5, x0, 5
// N+1: addi x6, x5, 3      // needs x5
assign forward_a_from_ex_mem = ex_mem.valid && ex_mem.rf_wr_en && (ex_mem.rd_addr != 0) && (ex_mem.rd_addr == id_ex.rs1_addr);
assign forward_b_from_ex_mem = ex_mem.valid && ex_mem.rf_wr_en && (ex_mem.rd_addr != 0) && (ex_mem.rd_addr == id_ex.rs2_addr);

assign forward_a_from_mem_wb = mem_wb.valid && mem_wb.rf_wr_en && (mem_wb.rd_addr != 0) && (mem_wb.rd_addr == id_ex.rs1_addr) && !forward_a_from_ex_mem;

assign forward_b_from_mem_wb = mem_wb.valid && mem_wb.rf_wr_en && (mem_wb.rd_addr != 0) && (mem_wb.rd_addr == id_ex.rs2_addr) && !forward_b_from_ex_mem;

assign rs1_data_resolved = forward_a_from_ex_mem ? ex_mem.alu_res : forward_a_from_mem_wb ? wb_data : id_ex.rs1_data;
assign rs2_data_resolved = forward_b_from_ex_mem ? ex_mem.alu_res : forward_b_from_mem_wb ? wb_data : id_ex.rs2_data;

assign ex_alu_a = id_ex.op1_sel ? id_ex.pc        : rs1_data_resolved;
assign ex_alu_b = id_ex.op2_sel ? id_ex.immediate : rs2_data_resolved;

alu u_alu (
    .alu_a   (ex_alu_a),
    .alu_b   (ex_alu_b),
    .alu_op  (id_ex.alu_op),
    
    .alu_res (ex_alu_res)
);

branch_control u_branch_control (
    .opr_a        (rs1_data_resolved),
    .opr_b        (rs2_data_resolved),
    .is_b_type    (id_ex.is_b_type),
    .funct3       (id_ex.funct3),
    .branch_taken (ex_branch_taken)
);

assign ex_branch_target = {ex_alu_res[31:1], 1'b0};
assign ex_next_seq_pc   = id_ex.pc + 32'd4;

// --------------------------------------------------------
// EX / MEM  register
// --------------------------------------------------------
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) ex_mem <= '0;
  else begin
    ex_mem.valid            <= id_ex.valid && !branch_redirect;
    ex_mem.alu_res          <= ex_alu_res;
    ex_mem.rs2_data         <= rs2_data_resolved;
    ex_mem.immediate        <= id_ex.immediate;
    ex_mem.next_seq_pc      <= ex_next_seq_pc;
    ex_mem.branch_target    <= ex_branch_target;
    ex_mem.rd_addr          <= id_ex.rd_addr;
    ex_mem.branch_taken     <= ex_branch_taken;
    ex_mem.pc_sel           <= id_ex.pc_sel;
    ex_mem.dmem_req         <= id_ex.dmem_req;
    ex_mem.dmem_wr_en       <= id_ex.dmem_wr_en;
    ex_mem.dmem_size        <= id_ex.dmem_size;
    ex_mem.dmem_zero_extend <= id_ex.dmem_zero_extend;
    ex_mem.rf_wr_en         <= id_ex.rf_wr_en;
    ex_mem.rf_wr_data_sel   <= id_ex.rf_wr_data_sel;
  end
end

// --------------------------------------------------------
// MEM stage bus
//   Side effects are gated with ex_mem.valid so bubbles do not issue
//   platform memory or MMIO transactions.
// --------------------------------------------------------
assign dmem_req         = ex_mem.valid && ex_mem.dmem_req;
assign dmem_wr_en       = ex_mem.dmem_wr_en;
assign dmem_data_size   = ex_mem.dmem_size;
assign dmem_addr        = ex_mem.alu_res;
assign dmem_wr_data     = ex_mem.rs2_data;
assign dmem_zero_extend = ex_mem.dmem_zero_extend;

// --------------------------------------------------------
// MEM / WB  register
//   dmem_rd_data is provided by the SoC memory system in the WB cycle.
// --------------------------------------------------------
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) mem_wb <= '0;
  else begin
    mem_wb.valid          <= ex_mem.valid;
    mem_wb.alu_res        <= ex_mem.alu_res;
    mem_wb.immediate      <= ex_mem.immediate;
    mem_wb.next_seq_pc    <= ex_mem.next_seq_pc;
    mem_wb.rd_addr        <= ex_mem.rd_addr;
    mem_wb.rf_wr_en       <= ex_mem.rf_wr_en;
    mem_wb.rf_wr_data_sel <= ex_mem.rf_wr_data_sel;
  end
end

// --------------------------------------------------------
// WB stage : writeback mux. Sync write happens inside
// register_file at posedge, gated by (mem_wb.valid & rf_wr_en).
// --------------------------------------------------------
always_comb begin
  case (mem_wb.rf_wr_data_sel)
    WB_SRC_ALU : wb_data = mem_wb.alu_res;
    WB_SRC_MEM : wb_data = dmem_rd_data;
    WB_SRC_IMM : wb_data = mem_wb.immediate;
    WB_SRC_PC  : wb_data = mem_wb.next_seq_pc;
  endcase
end

endmodule
