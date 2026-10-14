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
  input logic [31:0] irq_pending,
  input logic [63:0] time_value,

  output logic        imem_req,
  output logic [31:0] imem_addr,
  input  logic [31:0] imem_data,
  input  logic        imem_ready,
  input  logic        imem_rd_data_valid,

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
logic        fetch_stall;
logic        fetch_transaction_stall;
logic        imem_fire;
logic        imem_pending_q;
logic        imem_inflight_q;
logic        imem_done_q;
logic [31:0] imem_req_pc_q;
logic [31:0] imem_done_pc_q;
logic [31:0] imem_done_data_q;
logic        load_use_stall;
logic        memory_stall;
logic        execute_stall;
logic        pipeline_stall;
logic        branch_redirect;
logic        trap_redirect;
logic        mret_redirect;
logic        sret_redirect;
logic        interrupt_request;
logic        interrupt_take;
logic        branch_redirect_fire;
logic        redirect_fire;
logic        retire_squash_request;
logic        retire_squash;
logic [31:0] redirect_target;
logic        retire_barrier_resume_redirect;

typedef enum logic [1:0] {
  RETIRE_BARRIER_IDLE,
  RETIRE_BARRIER_DRAIN,
  RETIRE_BARRIER_RECHECK
} retire_barrier_state_t;

retire_barrier_state_t  retire_barrier_state_q;
retire_barrier_action_t retire_barrier_action_q;
retire_barrier_action_t ex_retire_barrier_action;
logic                   retire_barrier_active;
logic                   retire_barrier_start;
logic                   retire_barrier_commit;
logic [31:0]            retire_barrier_resume_pc_q;
logic                   retire_barrier_sret_q;
logic [31:0]            sfence_vma_vaddr_q;
logic [31:0]            sfence_vma_asid_q;
logic                   sfence_vma_flush;

// IF/ID equivalent: pc piped one cycle to align with the
// sync imem output reg, which acts as IF/ID.instruction.
logic        if_id_valid;
logic [31:0] if_id_pc;
logic [31:0] if_id_instruction;

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
logic        id_system_type;
logic [11:0] id_csr_addr;
logic [31:0] id_immediate;

logic [31:0] id_rs1_data, id_rs2_data;

logic        id_pc_sel, id_op1_sel, id_op2_sel;
alu_op_t     id_alu_op;
wb_src_t     id_rf_wr_data_sel;
logic        id_dmem_req, id_dmem_wr_en, id_dmem_zero_extend;
mem_size_t   id_dmem_size;
logic        id_rf_wr_en;
logic        id_uses_rs1, id_uses_rs2;
logic        id_csr_req, id_csr_imm_sel;
logic        id_fence_i;
logic        id_sfence_vma;
logic        id_mul_div_req;
logic        id_atomic_req;
csr_op_t     id_csr_op;
mul_div_op_t id_mul_div_op;
atomic_op_t  id_atomic_op;
retire_action_t id_retire_action;
trap_cause_t id_trap_cause;
trap_payload_t id_trap;

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
logic        csr_commit;
logic        trap_commit;
logic        mret_commit;
logic        sret_commit;
logic        fence_i_commit;
logic        sfence_vma_commit;
logic        retire_commit;
logic        instret_commit;
logic        mem_wb_committed;
logic        dmem_inflight;
logic        dmem_fire;
logic        dmem_done_q;
logic [31:0] dmem_done_rd_data_q;
logic        normal_dmem_req;
logic        normal_mem_ready;
logic        normal_mem_resp_valid;
logic [31:0] normal_mem_rd_data;
logic        atomic_unit_req;
logic        atomic_unit_ready;
logic        atomic_fire;
logic        atomic_inflight_q;
logic        atomic_resp_valid;
logic        atomic_done_q;
logic [31:0] atomic_result;
logic [31:0] atomic_done_result_q;
logic        atomic_mem_req;
logic        atomic_mem_wr_en;
logic [31:0] atomic_mem_addr;
logic [31:0] atomic_mem_wr_data;
logic        atomic_mem_ready;
logic        atomic_mem_resp_valid;
logic [31:0] atomic_mem_rd_data;
logic        atomic_exclusive_active;
logic        arbiter_write_valid;
logic [31:0] arbiter_write_addr;
logic        memory_complete;
logic        mul_div_unit_req;
logic        mul_div_unit_ready;
logic        mul_div_resp_valid;
logic        mul_div_fire;
logic        mul_div_inflight_q;
logic        mul_div_done_q;
logic [31:0] mul_div_result;
logic [31:0] mul_div_done_result_q;
logic [31:0] ex_mul_div_result;
logic        execute_complete;

logic forward_a_from_ex_mem;
logic forward_b_from_ex_mem;

logic forward_a_from_mem_wb;
logic forward_b_from_mem_wb;


logic [31:0] rs1_data_resolved;
logic [31:0] rs2_data_resolved;
logic [31:0] ex_mem_forward_data;
logic [31:0] ex_csr_src_data;
logic [31:0] ex_csr_rd_data;
logic [31:0] ex_csr_old_data;
logic [31:0] ex_csr_wr_data;
logic        ex_csr_src_zero;
logic        ex_csr_wr_en;
logic        csr_access_illegal;
logic        ex_illegal_csr_access;
logic        ex_illegal_mret;
logic        ex_illegal_sret;
logic        ex_illegal_sfence_vma;
logic [31:0] ex_system_instruction;
privilege_mode_t current_privilege;
retire_action_t ex_retire_action;
trap_payload_t ex_trap;
logic        ex_load_store_misaligned;
logic        ex_inst_addr_misaligned;
logic [31:0] csr_mtvec;
logic [31:0] csr_stvec;
logic [31:0] csr_mepc;
logic [31:0] csr_sepc;
logic [31:0] csr_satp;
logic        csr_mstatus_mprv;
privilege_mode_t csr_mstatus_mpp;
logic        csr_mstatus_sum;
logic        csr_mstatus_mxr;
logic        csr_mstatus_tvm;
logic        trap_to_supervisor;
logic        csr_sret_blocked;
logic        irq_valid;
interrupt_cause_t irq_cause;
logic [31:0] interrupt_mepc;
logic [31:0] trap_tvec;
logic [31:0] trap_vector;
logic [31:0] interrupt_vector;
trap_payload_t interrupt_trap;
trap_payload_t csr_trap;
// --------------------------------------------------------
// Fetch gate
//   Empty front-half => safe to fetch. mem_wb.valid is NOT
//   in the mask: WB has no effect on the address stream,
//   and the regfile write at end of WB lands BEFORE the
//   next instruction's ID-stage regfile read.
// --------------------------------------------------------
assign dmem_fire = normal_dmem_req && normal_mem_ready;
assign memory_stall = ex_mem.valid &&
                      (ex_mem.retire_action == RETIRE_NORMAL) &&
                      ex_mem.dmem_req &&
                      !memory_complete;
assign memory_complete = ex_mem.atomic_req ?
                         (atomic_resp_valid || atomic_done_q) :
                         (normal_mem_resp_valid || dmem_done_q);
assign fetch_transaction_stall = imem_pending_q ||
                                 (imem_inflight_q && !imem_rd_data_valid);
assign fetch_stall = fetch_enable || fetch_transaction_stall;
assign execute_complete = mul_div_resp_valid || mul_div_done_q;
assign execute_stall = id_ex.valid && id_ex.mul_div_req && !execute_complete;
assign pipeline_stall = load_use_stall || memory_stall || fetch_stall || execute_stall;
assign fetch_enable = !interrupt_request && !retire_squash_request && !branch_redirect &&
                      !memory_stall && !execute_stall &&
                      !retire_barrier_active &&
                      (ex_retire_barrier_action == RETIRE_BARRIER_NONE) &&
                      !imem_pending_q && !imem_inflight_q && !imem_done_q;
assign imem_fire = imem_req && imem_ready;

always_comb begin
  ex_retire_barrier_action = RETIRE_BARRIER_NONE;

  if (id_ex.valid &&
      (((id_ex.retire_action == RETIRE_MRET) &&
        (current_privilege == PRIVILEGE_M)) ||
       ((id_ex.retire_action == RETIRE_SRET) &&
        (current_privilege != PRIVILEGE_U) &&
        !csr_sret_blocked))) begin
    ex_retire_barrier_action = RETIRE_BARRIER_TRAP_RETURN;
  end else if (id_ex.valid &&
               (id_ex.retire_action == RETIRE_NORMAL) &&
               ex_csr_wr_en &&
               !csr_access_illegal) begin
    ex_retire_barrier_action = RETIRE_BARRIER_INTERRUPT_RECHECK;
  end else if (id_ex.valid && id_ex.fence_i) begin
    ex_retire_barrier_action = RETIRE_BARRIER_FENCE_I;
  end else if (id_ex.valid && id_ex.sfence_vma && !ex_illegal_sfence_vma) begin
    ex_retire_barrier_action = RETIRE_BARRIER_SFENCE_VMA;
  end
end

assign retire_barrier_active = (retire_barrier_state_q != RETIRE_BARRIER_IDLE);
assign retire_barrier_start = (retire_barrier_state_q == RETIRE_BARRIER_IDLE) &&
                              (ex_retire_barrier_action != RETIRE_BARRIER_NONE) &&
                              !redirect_fire && !retire_squash &&
                              !memory_stall && !fetch_transaction_stall;
assign retire_barrier_commit = (retire_barrier_state_q == RETIRE_BARRIER_DRAIN) &&
                               (((retire_barrier_action_q == RETIRE_BARRIER_TRAP_RETURN) &&
                                 (mret_commit || sret_commit)) ||
                                ((retire_barrier_action_q == RETIRE_BARRIER_INTERRUPT_RECHECK) && csr_commit) ||
                                ((retire_barrier_action_q == RETIRE_BARRIER_FENCE_I) && fence_i_commit) ||
                                ((retire_barrier_action_q == RETIRE_BARRIER_SFENCE_VMA) && sfence_vma_commit));
assign sfence_vma_flush = sfence_vma_commit;

// --------------------------------------------------------
// Branch / jump redirect
//   Decided in EX, observed via EX/MEM register.
// --------------------------------------------------------
assign branch_redirect = ex_mem.valid &&
                         (ex_mem.retire_action == RETIRE_NORMAL) &&
                         (ex_mem.branch_taken || ex_mem.pc_sel);
assign trap_redirect = trap_commit;
assign mret_redirect = mret_commit && !retire_barrier_active;
assign sret_redirect = sret_commit && !retire_barrier_active;
assign interrupt_request = irq_valid &&
                           (!retire_barrier_active ||
                            (retire_barrier_state_q == RETIRE_BARRIER_RECHECK)) &&
                           !trap_commit &&
                           !mret_commit &&
                           !sret_commit &&
                           !csr_commit &&
                           !memory_stall && !execute_stall &&
                           (!ex_mem.valid || (ex_mem.retire_action == RETIRE_NORMAL));
assign interrupt_take = interrupt_request && !fetch_transaction_stall;
assign branch_redirect_fire = branch_redirect && !memory_stall && !fetch_transaction_stall;
assign retire_barrier_resume_redirect =
    (retire_barrier_state_q == RETIRE_BARRIER_RECHECK) && !irq_valid;
assign redirect_fire = trap_redirect || mret_redirect || sret_redirect || interrupt_take ||
                       retire_barrier_resume_redirect || branch_redirect_fire;
assign trap_tvec = trap_to_supervisor ? csr_stvec : csr_mtvec;
assign trap_vector = {trap_tvec[31:2], 2'b00};
assign interrupt_vector = (trap_tvec[1:0] == 2'b01) ?
                          trap_vector + ({27'h0, irq_cause} << 2) :
                          trap_vector;
assign redirect_target = trap_redirect ? trap_vector :
                         mret_redirect ? csr_mepc :
                         sret_redirect ? csr_sepc :
                         interrupt_take ? interrupt_vector :
                         retire_barrier_resume_redirect ? retire_barrier_resume_pc_q :
                         ex_mem.branch_target;
assign retire_squash_request = ex_mem.valid &&
                               ((ex_mem.retire_action == RETIRE_TRAP) ||
                                (ex_mem.retire_action == RETIRE_MRET) ||
                                (ex_mem.retire_action == RETIRE_SRET));
assign retire_squash = retire_squash_request && !memory_stall && !fetch_transaction_stall;

always_comb begin
  if (retire_barrier_state_q == RETIRE_BARRIER_RECHECK) begin
    interrupt_mepc = retire_barrier_resume_pc_q;
  end else if (branch_redirect) begin
    interrupt_mepc = ex_mem.branch_target;
  end else if (id_ex.valid) begin
    interrupt_mepc = id_ex.pc;
  end else if (if_id_valid) begin
    interrupt_mepc = if_id_pc;
  end else begin
    interrupt_mepc = pc;
  end

  interrupt_trap.mepc = interrupt_mepc;
  interrupt_trap.mcause = {1'b1, 26'h0, irq_cause};
  interrupt_trap.mtval = 32'h0;

  csr_trap = interrupt_take ? interrupt_trap : mem_wb.trap;
end

// --------------------------------------------------------
// PC register
//   Priority: redirect (overrides any prediction) > fetch (+4).
//   Otherwise hold.
// --------------------------------------------------------
always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n)                 pc <= RESET_PC;
  else if (redirect_fire)       pc <= redirect_target;
  else if (!retire_barrier_active && !retire_barrier_start && imem_rd_data_valid)
                                  pc <= imem_req_pc_q + 32'd4;
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    retire_barrier_state_q <= RETIRE_BARRIER_IDLE;
    retire_barrier_action_q <= RETIRE_BARRIER_NONE;
    retire_barrier_resume_pc_q <= RESET_PC;
    retire_barrier_sret_q <= 1'b0;
    sfence_vma_vaddr_q <= 32'h0;
    sfence_vma_asid_q <= 32'h0;
  end else begin
    unique case (retire_barrier_state_q)
      RETIRE_BARRIER_IDLE: begin
        if (retire_barrier_start) begin
          retire_barrier_state_q <= RETIRE_BARRIER_DRAIN;
          retire_barrier_action_q <= ex_retire_barrier_action;
          retire_barrier_resume_pc_q <= ex_next_seq_pc;
          retire_barrier_sret_q <= (id_ex.retire_action == RETIRE_SRET);
          if (ex_retire_barrier_action == RETIRE_BARRIER_SFENCE_VMA) begin
            sfence_vma_vaddr_q <= rs1_data_resolved;
            sfence_vma_asid_q <= rs2_data_resolved;
          end
        end
      end

      RETIRE_BARRIER_DRAIN: begin
        if (retire_barrier_commit) begin
          retire_barrier_state_q <= RETIRE_BARRIER_RECHECK;
          if (retire_barrier_action_q == RETIRE_BARRIER_TRAP_RETURN) begin
            retire_barrier_resume_pc_q <= retire_barrier_sret_q ? csr_sepc : csr_mepc;
          end
        end
      end

      RETIRE_BARRIER_RECHECK: begin
        retire_barrier_state_q <= RETIRE_BARRIER_IDLE;
        retire_barrier_action_q <= RETIRE_BARRIER_NONE;
        retire_barrier_sret_q <= 1'b0;
      end

      default: begin
        retire_barrier_state_q <= RETIRE_BARRIER_IDLE;
        retire_barrier_action_q <= RETIRE_BARRIER_NONE;
        retire_barrier_sret_q <= 1'b0;
      end
    endcase
  end
end

// --------------------------------------------------------
// IF/ID boundary
//   imem_req gates the BRAM read so imem_data is preserved
//   across the cycles where the pipe is busy. pc_pipe carries
//   the pc of the instruction whose word is arriving next cycle.
// --------------------------------------------------------
assign imem_req  = imem_pending_q;
assign imem_addr = imem_req_pc_q;

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    imem_pending_q <= 1'b0;
    imem_inflight_q <= 1'b0;
    imem_done_q <= 1'b0;
    imem_req_pc_q <= RESET_PC;
    imem_done_pc_q <= RESET_PC;
    imem_done_data_q <= 32'h0;
  end else if (redirect_fire) begin
    imem_pending_q <= 1'b0;
    imem_inflight_q <= 1'b0;
    imem_done_q <= 1'b0;
    imem_req_pc_q <= redirect_target;
  end else if (retire_barrier_start || retire_barrier_active) begin
    // Discard all fetch state younger than the barrier instruction.
    imem_pending_q <= 1'b0;
    imem_inflight_q <= 1'b0;
    imem_done_q <= 1'b0;
    if (retire_barrier_active) begin
      imem_req_pc_q <= retire_barrier_resume_pc_q;
    end
  end else begin
    if (fetch_enable) begin
      imem_pending_q <= 1'b1;
      imem_req_pc_q <= pc;
    end

    if (imem_fire) begin
      imem_pending_q <= 1'b0;
      imem_inflight_q <= 1'b1;
    end

    if (imem_rd_data_valid) begin
      imem_inflight_q <= 1'b0;
    end

    if (imem_rd_data_valid && (load_use_stall || memory_stall || execute_stall)) begin
      imem_done_q <= 1'b1;
      imem_done_pc_q <= imem_req_pc_q;
      imem_done_data_q <= imem_data;
    end else if (imem_done_q && !load_use_stall && !memory_stall &&
                 !fetch_stall && !execute_stall) begin
      imem_done_q <= 1'b0;
    end
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    if_id_valid <= 1'b0;
    if_id_pc    <= RESET_PC;
    if_id_instruction <= 32'h0;
  end else if (redirect_fire || retire_squash ||
               retire_barrier_start || retire_barrier_active) begin
    // Defensive: squash any speculative fetch behind redirect/trap.
    // CONTROL HAZARD: IF/ID flush
    if_id_valid <= 1'b0;
  end else if (pipeline_stall) begin
    // hold PC and IF/ID
  end else if (imem_done_q || imem_rd_data_valid) begin
    if_id_valid <= 1'b1;
    if_id_pc <= imem_done_q ? imem_done_pc_q : imem_req_pc_q;
    if_id_instruction <= imem_done_q ? imem_done_data_q : imem_data;
  end else begin
    if_id_valid <= 1'b0;
  end
end

// --------------------------------------------------------
// ID stage : decode + control + regfile read
//   Consumes (if_id_valid, if_id_pc, imem_data). Outputs are
//   combinational and feed the ID/EX register.
// --------------------------------------------------------
decode u_decode (
    .instruction (if_id_instruction),
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
    .system_type (id_system_type),
    .csr_addr    (id_csr_addr),
    .immediate   (id_immediate)
);

control u_control (
    .r_type           (id_r_type),
    .i_type           (id_i_type),
    .s_type           (id_s_type),
    .b_type           (id_b_type),
    .u_type           (id_u_type),
    .j_type           (id_j_type),
    .system_type      (id_system_type),
    .funct3           (id_funct3),
    .funct7           (id_funct7),
    .opcode           (id_opcode),
    .csr_addr         (id_csr_addr),
    .rs2_addr         (id_rs2_addr),
    .rd_addr          (id_rd_addr),

    .pc_sel           (id_pc_sel),
    .op1_sel          (id_op1_sel),
    .op2_sel          (id_op2_sel),
    .alu_op           (id_alu_op),
    .rf_wr_data_sel   (id_rf_wr_data_sel),
    .dmem_req         (id_dmem_req),
    .dmem_size        (id_dmem_size),
    .dmem_wr_en       (id_dmem_wr_en),
    .dmem_zero_extend (id_dmem_zero_extend),
    .rf_wr_en         (id_rf_wr_en),
    .uses_rs1         (id_uses_rs1),
    .uses_rs2         (id_uses_rs2),
    .csr_req          (id_csr_req),
    .csr_op           (id_csr_op),
    .csr_imm_sel      (id_csr_imm_sel),
    .fence_i          (id_fence_i),
    .sfence_vma       (id_sfence_vma),
    .mul_div_req      (id_mul_div_req),
    .mul_div_op       (id_mul_div_op),
    .atomic_req       (id_atomic_req),
    .atomic_op        (id_atomic_op),
    .retire_action    (id_retire_action),
    .trap_cause       (id_trap_cause)
);

// Regfile: combinational read in ID, sync write from WB.
// Write enable is gated by mem_wb.valid so bubbles don't write.
assign retire_commit = mem_wb.valid && !mem_wb_committed;
assign wb_commit = retire_commit && (mem_wb.retire_action == RETIRE_NORMAL) && mem_wb.rf_wr_en;
assign csr_commit = retire_commit && (mem_wb.retire_action == RETIRE_NORMAL) && mem_wb.csr_wr_en;
assign trap_commit = retire_commit && (mem_wb.retire_action == RETIRE_TRAP);
assign mret_commit = retire_commit && (mem_wb.retire_action == RETIRE_MRET);
assign sret_commit = retire_commit && (mem_wb.retire_action == RETIRE_SRET);
assign fence_i_commit = retire_commit && mem_wb.fence_i;
assign sfence_vma_commit = retire_commit && mem_wb.sfence_vma;
assign instret_commit = retire_commit && (mem_wb.retire_action != RETIRE_TRAP);

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

csr_file u_csr_file (
    .clk         (clk),
    .reset_n     (reset_n),
    .rd_addr     (id_ex.csr_addr),
    .rd_data     (ex_csr_rd_data),
    .access_wr_en(ex_csr_wr_en),
    .access_illegal(csr_access_illegal),
    .wr_en       (csr_commit),
    .wr_addr     (mem_wb.csr_addr),
    .wr_data     (mem_wb.csr_wr_data),
    .instret_inc (instret_commit),
    .time_value  (time_value),
    .irq_pending (irq_pending),
    .irq_valid   (irq_valid),
    .irq_cause   (irq_cause),
    .trap_enter  (trap_commit || interrupt_take),
    .trap        (csr_trap),
    .mret_enter  (mret_commit),
    .sret_enter  (sret_commit),
    .mtvec       (csr_mtvec),
    .stvec       (csr_stvec),
    .mepc        (csr_mepc),
    .sepc        (csr_sepc),
    .satp        (csr_satp),
    .mstatus_mprv(csr_mstatus_mprv),
    .mstatus_mpp (csr_mstatus_mpp),
    .mstatus_sum (csr_mstatus_sum),
    .mstatus_mxr (csr_mstatus_mxr),
    .mstatus_tvm (csr_mstatus_tvm),
    .trap_to_supervisor(trap_to_supervisor),
    .sret_blocked(csr_sret_blocked),
    .current_privilege(current_privilege)
);

always_comb begin
  ex_csr_old_data = ex_csr_rd_data;

  if (ex_mem.valid &&
      (ex_mem.retire_action == RETIRE_NORMAL) &&
      ex_mem.csr_wr_en &&
      (ex_mem.csr_addr == id_ex.csr_addr)) begin
    ex_csr_old_data = ex_mem.csr_wr_data;
  end else if (mem_wb.valid &&
               !mem_wb_committed &&
               (mem_wb.retire_action == RETIRE_NORMAL) &&
               mem_wb.csr_wr_en &&
               (mem_wb.csr_addr == id_ex.csr_addr)) begin
    ex_csr_old_data = mem_wb.csr_wr_data;
  end
end

always_comb begin
  id_trap = '0;

  if (id_retire_action == RETIRE_TRAP) begin
    id_trap.mepc = if_id_pc;
    if (id_trap_cause == TRAP_CAUSE_ECALL_M) begin // all ecall is decoded as ecall_m
      unique case (current_privilege)
        PRIVILEGE_U: id_trap.mcause = {28'h0, TRAP_CAUSE_ECALL_U};
        PRIVILEGE_S: id_trap.mcause = {28'h0, TRAP_CAUSE_ECALL_S};
        default:     id_trap.mcause = {28'h0, TRAP_CAUSE_ECALL_M};
      endcase
    end else begin
      id_trap.mcause = {28'h0, id_trap_cause};
    end
    id_trap.mtval = (id_trap_cause == TRAP_CAUSE_ILLEGAL_INSTRUCTION) ? if_id_instruction : 32'h0;
  end
end

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

  if(id_uses_rs1 && id_ex.valid && id_ex.rf_wr_en && (id_ex.rd_addr != 0) && (id_ex.rd_addr == id_rs1_addr)) id_fwd_a_sel = FWD_EXMEM;

  else if (id_uses_rs1 && ex_mem.valid && ex_mem.rf_wr_en && (ex_mem.rd_addr != 0) && (ex_mem.rd_addr == id_rs1_addr)) id_fwd_a_sel = FWD_MEMWB;

  if(id_uses_rs2 && id_ex.valid && id_ex.rf_wr_en && (id_ex.rd_addr != 0) && (id_ex.rd_addr == id_rs2_addr)) id_fwd_b_sel = FWD_EXMEM;

  else if (id_uses_rs2 && ex_mem.valid && ex_mem.rf_wr_en && (ex_mem.rd_addr != 0) && (ex_mem.rd_addr == id_rs2_addr)) id_fwd_b_sel = FWD_MEMWB;
end


always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) id_ex <= '0;
  else if (redirect_fire || retire_squash) id_ex <= '0;
  else if (memory_stall || fetch_stall || execute_stall) begin
    // Hold pipeline state while memory or instruction fetch is waiting.
  end
  else if (retire_barrier_start || retire_barrier_active) id_ex <= '0;
  else if (load_use_stall) id_ex <= '0;
  else begin
    id_ex.valid            <= if_id_valid && !redirect_fire; // CONTROL/TRAP HAZARD: ID/EX flush
    id_ex.pc               <= if_id_pc;
    id_ex.rs1_data         <= id_rs1_data;
    id_ex.rs2_data         <= id_rs2_data;
    id_ex.immediate        <= id_immediate;
    id_ex.rs1_addr         <= id_rs1_addr;
    id_ex.rd_addr          <= id_rd_addr;
    id_ex.uses_rs1         <= id_uses_rs1;
    id_ex.uses_rs2         <= id_uses_rs2;
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
    id_ex.csr_req          <= id_csr_req;
    id_ex.csr_addr         <= id_csr_addr;
    id_ex.csr_op           <= id_csr_op;
    id_ex.csr_imm_sel      <= id_csr_imm_sel;
    id_ex.fence_i          <= id_fence_i;
    id_ex.sfence_vma       <= id_sfence_vma;
    id_ex.mul_div_req      <= id_mul_div_req;
    id_ex.mul_div_op       <= id_mul_div_op;
    id_ex.atomic_req       <= id_atomic_req;
    id_ex.atomic_op        <= id_atomic_op;
    id_ex.retire_action    <= id_retire_action;
    id_ex.trap             <= id_trap;
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
assign load_use_stall = id_ex.valid && id_ex.load_from_memory
                        && ((id_uses_rs1 && (id_ex.rd_addr == id_rs1_addr)) ||
                            (id_uses_rs2 && (id_ex.rd_addr == id_rs2_addr)))
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

assign mul_div_unit_req = id_ex.valid && id_ex.mul_div_req &&
                          !mul_div_inflight_q && !mul_div_done_q &&
                          !redirect_fire && !retire_squash;
assign mul_div_fire = mul_div_unit_req && mul_div_unit_ready;
assign ex_mul_div_result = mul_div_done_q ? mul_div_done_result_q : mul_div_result;

mul_div u_mul_div (
    .clk        (clk),
    .reset_n    (reset_n),
    .req        (mul_div_unit_req),
    .ready      (mul_div_unit_ready),
    .op         (id_ex.mul_div_op),
    .lhs        (rs1_data_resolved),
    .rhs        (rs2_data_resolved),
    .resp_valid (mul_div_resp_valid),
    .result     (mul_div_result)
);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    mul_div_inflight_q <= 1'b0;
    mul_div_done_q <= 1'b0;
    mul_div_done_result_q <= 32'h0;
  end else begin
    if (mul_div_fire) begin
      mul_div_inflight_q <= 1'b1;
    end
    if (mul_div_resp_valid) begin
      mul_div_inflight_q <= 1'b0;
      mul_div_done_result_q <= mul_div_result;
      mul_div_done_q <= memory_stall || fetch_stall;
    end else if (mul_div_done_q && !memory_stall && !fetch_stall) begin
      mul_div_done_q <= 1'b0;
    end
  end
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
    WB_SRC_ALU: ex_mem_forward_data = id_ex.mul_div_req ? ex_mul_div_result : ex_alu_res;
    WB_SRC_IMM: ex_mem_forward_data = id_ex.immediate;
    WB_SRC_PC:  ex_mem_forward_data = ex_next_seq_pc;
    WB_SRC_CSR: ex_mem_forward_data = ex_csr_old_data;
    default:    ex_mem_forward_data = 32'h0;
  endcase
end

assign ex_csr_src_data = id_ex.csr_imm_sel ? id_ex.immediate : rs1_data_resolved;
assign ex_csr_src_zero = (id_ex.rs1_addr == 5'h0);

always_comb begin
  unique case (id_ex.csr_op)
    CSR_OP_RW: ex_csr_wr_data = ex_csr_src_data;
    CSR_OP_RS: ex_csr_wr_data = ex_csr_old_data | ex_csr_src_data;
    CSR_OP_RC: ex_csr_wr_data = ex_csr_old_data & ~ex_csr_src_data;
    default:   ex_csr_wr_data = ex_csr_src_data;
  endcase
end

assign ex_csr_wr_en = id_ex.csr_req &&
                      ((id_ex.csr_op == CSR_OP_RW) ||
                       ((id_ex.csr_op != CSR_OP_RW) && !ex_csr_src_zero));
assign ex_illegal_csr_access = id_ex.csr_req && csr_access_illegal;
assign ex_illegal_mret = (id_ex.retire_action == RETIRE_MRET) &&
                         (current_privilege != PRIVILEGE_M);
assign ex_illegal_sret = (id_ex.retire_action == RETIRE_SRET) &&
                         ((current_privilege == PRIVILEGE_U) || csr_sret_blocked);
assign ex_illegal_sfence_vma = id_ex.sfence_vma &&
                               ((current_privilege == PRIVILEGE_U) ||
                                ((current_privilege == PRIVILEGE_S) && csr_mstatus_tvm));
assign ex_system_instruction = {id_ex.csr_addr, id_ex.rs1_addr, id_ex.funct3,
                                id_ex.rd_addr, OPCODE_SYSTEM};

always_comb begin
  ex_inst_addr_misaligned = (id_ex.pc_sel || ex_branch_taken) && (ex_branch_target[1:0] != 2'b00);
  ex_load_store_misaligned = id_ex.dmem_req &&
                             (((id_ex.dmem_size == HALF_WORD) && ex_alu_res[0]) ||
                              ((id_ex.dmem_size == WORD) && (ex_alu_res[1:0] != 2'b00)));

  ex_retire_action = id_ex.retire_action;
  ex_trap = id_ex.trap;

  if (ex_illegal_csr_access || ex_illegal_mret || ex_illegal_sret ||
      ex_illegal_sfence_vma) begin
    ex_retire_action = RETIRE_TRAP;
    ex_trap.mepc = id_ex.pc;
    ex_trap.mcause = {28'h0, TRAP_CAUSE_ILLEGAL_INSTRUCTION};
    ex_trap.mtval = ex_system_instruction;
  end else if (id_ex.retire_action == RETIRE_NORMAL) begin
    if (ex_inst_addr_misaligned) begin
      ex_retire_action = RETIRE_TRAP;
      ex_trap.mepc = id_ex.pc;
      ex_trap.mcause = {28'h0, TRAP_CAUSE_INST_ADDR_MISALIGNED};
      ex_trap.mtval = ex_branch_target;
    end else if (ex_load_store_misaligned) begin
      ex_retire_action = RETIRE_TRAP;
      ex_trap.mepc = id_ex.pc;
      ex_trap.mcause = {28'h0, id_ex.dmem_wr_en ? TRAP_CAUSE_STORE_ADDR_MISALIGNED :
                                                 TRAP_CAUSE_LOAD_ADDR_MISALIGNED};
      ex_trap.mtval = ex_alu_res;
    end
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) ex_mem <= '0;
  else if (redirect_fire) ex_mem <= '0;
  else if (memory_stall || fetch_stall || execute_stall) begin
    // Hold active pipeline state until the stalled interface completes.
  end
  else if (retire_squash) ex_mem <= '0;
  else begin
    ex_mem.valid            <= id_ex.valid && !redirect_fire;
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
    ex_mem.atomic_req       <= id_ex.atomic_req;
    ex_mem.atomic_op        <= id_ex.atomic_op;
    ex_mem.rf_wr_en         <= id_ex.rf_wr_en;
    ex_mem.forward_data     <= ex_mem_forward_data;
    ex_mem.load_from_memory <= id_ex.load_from_memory;
    ex_mem.csr_wr_en        <= ex_csr_wr_en;
    ex_mem.csr_addr         <= id_ex.csr_addr;
    ex_mem.csr_wr_data      <= ex_csr_wr_data;
    ex_mem.fence_i          <= id_ex.fence_i;
    ex_mem.sfence_vma       <= id_ex.sfence_vma;
    ex_mem.retire_action    <= ex_retire_action;
    ex_mem.trap             <= ex_trap;
  end
end

// --------------------------------------------------------
// MEM stage bus
//   Side effects are gated with ex_mem.valid so bubbles do not issue
//   platform memory or MMIO transactions.
// --------------------------------------------------------
assign normal_dmem_req = ex_mem.valid &&
                         (ex_mem.retire_action == RETIRE_NORMAL) &&
                         ex_mem.dmem_req &&
                         !ex_mem.atomic_req &&
                         !dmem_inflight &&
                         !dmem_done_q;

assign atomic_unit_req = ex_mem.valid &&
                         (ex_mem.retire_action == RETIRE_NORMAL) &&
                         ex_mem.atomic_req &&
                         !atomic_inflight_q &&
                         !atomic_done_q;
assign atomic_fire = atomic_unit_req && atomic_unit_ready;

atomic_unit u_atomic_unit (
    .clk                    (clk),
    .reset_n                (reset_n),
    .req                    (atomic_unit_req),
    .ready                  (atomic_unit_ready),
    .op                     (ex_mem.atomic_op),
    .addr                   (ex_mem.alu_res),
    .operand                (ex_mem.rs2_data),
    .resp_valid             (atomic_resp_valid),
    .result                 (atomic_result),
    .mem_req                (atomic_mem_req),
    .mem_wr_en              (atomic_mem_wr_en),
    .mem_addr               (atomic_mem_addr),
    .mem_wr_data            (atomic_mem_wr_data),
    .mem_ready              (atomic_mem_ready),
    .mem_resp_valid         (atomic_mem_resp_valid),
    .mem_rd_data            (atomic_mem_rd_data),
    .clear_reservation      (trap_commit || interrupt_take),
    .local_write_valid      (arbiter_write_valid),
    .local_write_addr       (arbiter_write_addr),
    .external_write_valid   (1'b0),
    .external_write_addr    (32'h0),
    .exclusive_active       (atomic_exclusive_active)
);

memory_arbiter u_memory_arbiter (
    .clk                (clk),
    .reset_n            (reset_n),

    .normal_req         (normal_dmem_req),
    .normal_ready       (normal_mem_ready),
    .normal_wr_en       (ex_mem.dmem_wr_en),
    .normal_size        (ex_mem.dmem_size),
    .normal_addr        (ex_mem.alu_res),
    .normal_wr_data     (ex_mem.rs2_data),
    .normal_zero_extend (ex_mem.dmem_zero_extend),
    .normal_lock        (1'b0),
    .normal_resp_valid  (normal_mem_resp_valid),
    .normal_rd_data     (normal_mem_rd_data),

    .atomic_req         (atomic_mem_req),
    .atomic_ready       (atomic_mem_ready),
    .atomic_wr_en       (atomic_mem_wr_en),
    .atomic_size        (WORD),
    .atomic_addr        (atomic_mem_addr),
    .atomic_wr_data     (atomic_mem_wr_data),
    .atomic_zero_extend (1'b0),
    .atomic_lock        (atomic_exclusive_active),
    .atomic_resp_valid  (atomic_mem_resp_valid),
    .atomic_rd_data     (atomic_mem_rd_data),

    .ptw_req            (1'b0),
    .ptw_ready          (),
    .ptw_wr_en          (1'b0),
    .ptw_size           (WORD),
    .ptw_addr           (32'h0),
    .ptw_wr_data        (32'h0),
    .ptw_zero_extend    (1'b0),
    .ptw_lock           (1'b0),
    .ptw_resp_valid     (),
    .ptw_rd_data        (),

    .mem_req            (dmem_req),
    .mem_ready          (dmem_ready),
    .mem_wr_en          (dmem_wr_en),
    .mem_size           (dmem_data_size),
    .mem_addr           (dmem_addr),
    .mem_wr_data        (dmem_wr_data),
    .mem_zero_extend    (dmem_zero_extend),
    .mem_resp_valid     (dmem_rd_data_valid),
    .mem_rd_data        (dmem_rd_data),
    .write_valid        (arbiter_write_valid),
    .write_addr         (arbiter_write_addr)
);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    dmem_inflight <= 1'b0;
    dmem_done_q <= 1'b0;
    dmem_done_rd_data_q <= 32'h0;
  end else if (!ex_mem.atomic_req) begin
    if (dmem_fire && !normal_mem_resp_valid) begin
      dmem_inflight <= 1'b1;
    end else if (normal_mem_resp_valid) begin
      dmem_inflight <= 1'b0;
    end

    if (normal_mem_resp_valid && (fetch_stall || execute_stall)) begin
      dmem_done_q <= 1'b1;
      dmem_done_rd_data_q <= normal_mem_rd_data;
    end else if (!memory_stall && !fetch_stall && !execute_stall) begin
      dmem_done_q <= 1'b0;
    end
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    atomic_inflight_q <= 1'b0;
    atomic_done_q <= 1'b0;
    atomic_done_result_q <= 32'h0;
  end else begin
    if (atomic_fire) begin
      atomic_inflight_q <= 1'b1;
    end

    if (atomic_resp_valid) begin
      atomic_inflight_q <= 1'b0;
      atomic_done_result_q <= atomic_result;
      atomic_done_q <= fetch_stall || execute_stall;
    end else if (atomic_done_q && !memory_stall && !fetch_stall && !execute_stall) begin
      atomic_done_q <= 1'b0;
    end
  end
end

// --------------------------------------------------------
// MEM / WB  register
//   Load data is routed back from the memory arbiter's normal client.
// --------------------------------------------------------

// --------------------------------------------------------
// WB stage : writeback mux. Sync write happens inside
// register_file at posedge, gated by (mem_wb.valid & rf_wr_en).
// --------------------------------------------------------
always_comb begin
  if (ex_mem.atomic_req)
    wb_data = atomic_done_q ? atomic_done_result_q : atomic_result;
  else if (ex_mem.load_from_memory)
    wb_data = dmem_done_q ? dmem_done_rd_data_q : normal_mem_rd_data;
  else
    wb_data = ex_mem.forward_data;
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    mem_wb <= '0;
    mem_wb_committed <= 1'b0;
  end
  else if (memory_stall || fetch_stall || execute_stall) begin
    // Hold forwarding data stable, but allow this WB slot to retire once.
    if (retire_commit) mem_wb_committed <= 1'b1;
  end
  else begin
    mem_wb.valid          <= ex_mem.valid;
    mem_wb.rd_addr        <= ex_mem.rd_addr;
    mem_wb.rf_wr_en       <= ex_mem.rf_wr_en;
    mem_wb_committed      <= 1'b0;
    mem_wb.wb_data        <= wb_data;
    mem_wb.csr_wr_en      <= ex_mem.csr_wr_en;
    mem_wb.csr_addr       <= ex_mem.csr_addr;
    mem_wb.csr_wr_data    <= ex_mem.csr_wr_data;
    mem_wb.fence_i        <= ex_mem.fence_i;
    mem_wb.sfence_vma     <= ex_mem.sfence_vma;
    mem_wb.retire_action  <= ex_mem.retire_action;
    mem_wb.trap           <= ex_mem.trap;
  end
end

endmodule
