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

  output logic        imem_req,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_data,
  input  logic        imem_busy,

  output logic        dmem_req,
  output logic        dmem_wr_en,
  output mem_size_t   dmem_data_size,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wr_data,
  output logic        dmem_zero_extend,
  input  logic [31:0] dmem_rd_data,
  input  logic        dmem_ready,
  input  logic        dmem_rd_data_valid
);

// =====================================================
// IF stage
// =====================================================
logic [31:0] pc;
logic        fetch_enable;
logic        load_use_stall;
logic        memory_stall;
logic        pipeline_stall;
logic        branch_redirect;
logic        redirect_fire;
logic [31:0] redirect_target;

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
logic        wb_commit;
logic        mem_wb_committed;
logic        dmem_inflight;
logic        dmem_fire;

logic forward_a_from_ex_mem;
logic forward_b_from_ex_mem;

logic forward_a_from_mem_wb;
logic forward_b_from_mem_wb;


logic [31:0] rs1_data_resolved;
logic [31:0] rs2_data_resolved;
logic [31:0] ex_mem_forward_data;
// --------------------------------------------------------
// Fetch gate
//   Empty front-half => safe to fetch. mem_wb.valid is NOT
//   in the mask: WB has no effect on the address stream,
//   and the regfile write at end of WB lands BEFORE the
//   next instruction's ID-stage regfile read.
// --------------------------------------------------------
assign dmem_fire = dmem_req && dmem_ready;
assign memory_stall = ex_mem.valid &&
                      ex_mem.dmem_req &&
                      !dmem_rd_data_valid;
assign pipeline_stall = load_use_stall || memory_stall;
assign fetch_enable = !pipeline_stall && !imem_busy;

// --------------------------------------------------------
// Branch / jump redirect
//   Decided in EX, observed via EX/MEM register.
// --------------------------------------------------------
assign branch_redirect = ex_mem.valid && (ex_mem.branch_taken || ex_mem.pc_sel);
assign redirect_fire = branch_redirect && !memory_stall;
assign redirect_target = ex_mem.branch_target;

// --------------------------------------------------------
// PC register
//   Priority: redirect (overrides any prediction) > fetch (+4).
//   Otherwise hold.
// --------------------------------------------------------
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n)               pc <= RESET_PC;
  else if (redirect_fire)     pc <= redirect_target;
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
  end else if (redirect_fire) begin
    // Defensive: squash any speculative fetch behind the branch.
    // CONTROL HAZARD: IF/ID flush
    if_id_valid <= 1'b0;
  end else if (pipeline_stall) begin
    // hold PC and IF/ID
  end else begin
    if_id_valid <= fetch_enable;
    if_id_pc    <= pc;
  end
end

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
assign wb_commit = mem_wb.valid && mem_wb.rf_wr_en && !mem_wb_committed;

register_file u_register_file (
    .clk      (clk),
    .reset_n  (reset_n),
    .rs1_addr (id_rs1_addr),
    .rs2_addr (id_rs2_addr),
    .rd_addr  (mem_wb.rd_addr),
    .rf_wr_en (wb_commit),
    .wr_data  (mem_wb.wb_data),
    .rs1_data (id_rs1_data),
    .rs2_data (id_rs2_data)
);

// --------------------------------------------------------
// ID / EX  register
// --------------------------------------------------------
// DATA HAZARD (RAW): forwarding
// N:   addi x5, x0, 5
// N+1: addi x6, x5, 3      // needs x5

fwd_flag_t id_fwd_a_sel;
fwd_flag_t id_fwd_b_sel;

always_comb begin
  id_fwd_a_sel = FWD_RF;
  id_fwd_b_sel = FWD_RF;

  if(id_ex.valid && id_ex.rf_wr_en && (id_ex.rd_addr != 0) && (id_ex.rd_addr == id_rs1_addr)) id_fwd_a_sel = FWD_EXMEM;

  else if (ex_mem.valid && ex_mem.rf_wr_en && (ex_mem.rd_addr != 0) && (ex_mem.rd_addr == id_rs1_addr)) id_fwd_a_sel = FWD_MEMWB;

  if(id_ex.valid && id_ex.rf_wr_en && (id_ex.rd_addr != 0) && (id_ex.rd_addr == id_rs2_addr)) id_fwd_b_sel = FWD_EXMEM;

  else if (ex_mem.valid && ex_mem.rf_wr_en && (ex_mem.rd_addr != 0) && (ex_mem.rd_addr == id_rs2_addr)) id_fwd_b_sel = FWD_MEMWB;
end


always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) id_ex <= '0;
  else if (memory_stall) begin
    // Hold the instruction feeding MEM while the bus is busy
  end
  else if (load_use_stall) id_ex <= '0;
  else begin
    id_ex.valid            <= if_id_valid && !branch_redirect; // CONTROL HAZARD: ID/EX flush
    id_ex.pc               <= if_id_pc;
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
    id_ex.fwd_a_sel        <= id_fwd_a_sel;
    id_ex.fwd_b_sel        <= id_fwd_b_sel;
    id_ex.load_from_memory <= (id_rf_wr_data_sel == WB_SRC_MEM);
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

always_comb begin
  case (id_ex.fwd_a_sel)
    FWD_RF:    rs1_data_resolved = id_ex.rs1_data;
    FWD_EXMEM: rs1_data_resolved = ex_mem.forward_data;
    FWD_MEMWB: rs1_data_resolved = mem_wb.wb_data;
    default:   rs1_data_resolved = id_ex.rs1_data;
  endcase
  
  case (id_ex.fwd_b_sel)
    FWD_RF:    rs2_data_resolved = id_ex.rs2_data;
    FWD_EXMEM: rs2_data_resolved = ex_mem.forward_data;
    FWD_MEMWB: rs2_data_resolved = mem_wb.wb_data;
    default:   rs2_data_resolved = id_ex.rs2_data;
  endcase
end

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

always_comb begin
  unique case (id_ex.rf_wr_data_sel)
    WB_SRC_ALU: ex_mem_forward_data = ex_alu_res;
    WB_SRC_IMM: ex_mem_forward_data = id_ex.immediate;
    WB_SRC_PC:  ex_mem_forward_data = ex_next_seq_pc;
    default:    ex_mem_forward_data = 32'h0;
  endcase
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) ex_mem <= '0;
  else if (memory_stall) begin
    // Hold active memory operation stable until the bus completes it. 
  end
  else begin
    ex_mem.valid            <= id_ex.valid && !branch_redirect;
    ex_mem.alu_res          <= ex_alu_res;
    ex_mem.rs2_data         <= rs2_data_resolved;
    ex_mem.branch_target    <= ex_branch_target;
    ex_mem.rd_addr          <= id_ex.rd_addr;
    ex_mem.branch_taken     <= ex_branch_taken;
    ex_mem.pc_sel           <= id_ex.pc_sel;
    ex_mem.dmem_req         <= id_ex.dmem_req;
    ex_mem.dmem_wr_en       <= id_ex.dmem_wr_en;
    ex_mem.dmem_size        <= id_ex.dmem_size;
    ex_mem.dmem_zero_extend <= id_ex.dmem_zero_extend;
    ex_mem.rf_wr_en         <= id_ex.rf_wr_en;
    ex_mem.forward_data     <= ex_mem_forward_data;
    ex_mem.load_from_memory <= id_ex.load_from_memory;
  end
end

// --------------------------------------------------------
// MEM stage bus
//   Side effects are gated with ex_mem.valid so bubbles do not issue
//   platform memory or MMIO transactions.
// --------------------------------------------------------
assign dmem_req         = ex_mem.valid && ex_mem.dmem_req && !dmem_inflight;
assign dmem_wr_en       = ex_mem.dmem_wr_en;
assign dmem_data_size   = ex_mem.dmem_size;
assign dmem_addr        = ex_mem.alu_res;
assign dmem_wr_data     = ex_mem.rs2_data;
assign dmem_zero_extend = ex_mem.dmem_zero_extend;

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    dmem_inflight <= 1'b0;
  end else if (dmem_fire && !dmem_rd_data_valid) begin
    dmem_inflight <= 1'b1;
  end else if (dmem_rd_data_valid) begin
    dmem_inflight <= 1'b0;
  end
end

// --------------------------------------------------------
// MEM / WB  register
//   dmem_rd_data is provided by the SoC memory system in the WB cycle.
// --------------------------------------------------------

// --------------------------------------------------------
// WB stage : writeback mux. Sync write happens inside
// register_file at posedge, gated by (mem_wb.valid & rf_wr_en).
// --------------------------------------------------------
always_comb begin
  if (ex_mem.load_from_memory)
    wb_data = dmem_rd_data;
  else
    wb_data = ex_mem.forward_data;
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    mem_wb <= '0;
    mem_wb_committed <= 1'b0;
  end
  else if (memory_stall) begin
    // Hold forwarding data stable, but allow this WB slot to commit once.
    if (wb_commit) mem_wb_committed <= 1'b1;
  end
  else begin
    mem_wb.valid          <= ex_mem.valid;
    mem_wb.rd_addr        <= ex_mem.rd_addr;
    mem_wb.rf_wr_en       <= ex_mem.rf_wr_en;
    mem_wb_committed      <= 1'b0;
    mem_wb.wb_data        <= wb_data;
  end
end

endmodule
