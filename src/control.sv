// --------------------------------------------------------
// Control Unit - RTL (Aligned with refined risc_pkg)
// --------------------------------------------------------
import risc_pkg::*;

module control (
  // Instruction type flags
  input  logic       r_type,
  input  logic       i_type,
  input  logic       s_type,
  input  logic       b_type,
  input  logic       u_type,
  input  logic       j_type,
  input  logic       system_type,

  // Instruction fields
  input  logic [2:0] funct3,
  input  logic [6:0] funct7,
  input  logic [6:0] opcode,
  input  logic [11:0] csr_addr,

  // Outputs
  output logic        pc_sel,
  output logic        op1_sel,
  output logic        op2_sel,
  output alu_op_t	  alu_op,
  output wb_src_t	  rf_wr_data_sel,
  output logic        dmem_req,
  output mem_size_t   dmem_size,
  output logic        dmem_wr_en,
  output logic        dmem_zero_extend,
  output logic        rf_wr_en,
  output logic        uses_rs1,
  output logic        uses_rs2,
  output logic        csr_req,
  output csr_op_t     csr_op,
  output logic        csr_imm_sel,
  output logic        fence_i,
  output logic        mul_div_req,
  output mul_div_op_t mul_div_op,
  output retire_action_t retire_action,
  output trap_cause_t trap_cause
);

// --------------------------------------------------------
// Internal signals
// --------------------------------------------------------

logic [9:0] funct_r;
logic [3:0] opcode_i;
logic       funct7_bit5;

assign funct7_bit5 = funct7[5];

control_t ctrl_r, ctrl_i, ctrl_s, ctrl_b, ctrl_u, ctrl_j, ctrl_misc_mem, ctrl_system, ctrl;


// --------------------------------------------------------
// R-Type Control
// --------------------------------------------------------

assign funct_r = {funct7, funct3};

always_comb begin
    ctrl_r = '0;
    ctrl_r.retire_action = RETIRE_TRAP;
    ctrl_r.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;

    if (funct7 == 7'b0000001) begin
        ctrl_r = '0;
        ctrl_r.rf_write_enable = 1'b1;
        ctrl_r.uses_rs1 = 1'b1;
        ctrl_r.uses_rs2 = 1'b1;
        ctrl_r.mul_div_req = 1'b1;

        unique case (funct3)
            3'b000: ctrl_r.mul_div_op = MULDIV_MUL;
            3'b001: ctrl_r.mul_div_op = MULDIV_MULH;
            3'b010: ctrl_r.mul_div_op = MULDIV_MULHSU;
            3'b011: ctrl_r.mul_div_op = MULDIV_MULHU;
            3'b100: ctrl_r.mul_div_op = MULDIV_DIV;
            3'b101: ctrl_r.mul_div_op = MULDIV_DIVU;
            3'b110: ctrl_r.mul_div_op = MULDIV_REM;
            3'b111: ctrl_r.mul_div_op = MULDIV_REMU;
        endcase
    end else case (funct_r)
        R_ADD,
        R_SUB,
        R_AND,
        R_OR,
        R_XOR,
        R_SLL,
        R_SRL,
        R_SRA,
        R_SLT,
        R_SLTU: begin
            ctrl_r = '0;
            ctrl_r.rf_write_enable = 1'b1;
            ctrl_r.uses_rs1 = 1'b1;
            ctrl_r.uses_rs2 = 1'b1;

            case (funct_r)
                R_ADD  : ctrl_r.alu_op = ADD;
                R_SUB  : ctrl_r.alu_op = SUB;
                R_AND  : ctrl_r.alu_op = AND;
                R_OR   : ctrl_r.alu_op = OR;
                R_XOR  : ctrl_r.alu_op = XOR;
                R_SLL  : ctrl_r.alu_op = SLL;
                R_SRL  : ctrl_r.alu_op = SRL;
                R_SRA  : ctrl_r.alu_op = SRA;
                R_SLT  : ctrl_r.alu_op = SLT;
                R_SLTU : ctrl_r.alu_op = SLTU;
                default: ctrl_r.alu_op = ADD;
            endcase
        end
        default: begin
        end
    endcase
end

// --------------------------------------------------------
// I-Type Control
// --------------------------------------------------------

assign opcode_i = {opcode[4], funct3};

always_comb begin
    ctrl_i = '0;
    ctrl_i.retire_action = RETIRE_TRAP;
    ctrl_i.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;

    // JALR
    if (opcode == OPCODE_I_JALR) begin
      if (funct3 == 3'b000) begin
        ctrl_i = '0;
        ctrl_i.rf_write_enable = 1'b1;
        ctrl_i.uses_rs1 = 1'b1;
        ctrl_i.alu_src_b_select = 1'b1;
        ctrl_i.pc_src_select = 1'b1;
        ctrl_i.wb_src = WB_SRC_PC;
        ctrl_i.alu_op = ADD;
      end
    end else begin
      case (opcode_i)
          I_ADDI,
          I_ANDI,
          I_ORI,
          I_XORI,
          I_SLTI,
          I_SLTIU: begin
              ctrl_i = '0;
              ctrl_i.rf_write_enable = 1'b1;
              ctrl_i.uses_rs1 = 1'b1;
              ctrl_i.alu_src_b_select = 1'b1;

              case (opcode_i)
                  I_ADDI  : ctrl_i.alu_op = ADD;
                  I_ANDI  : ctrl_i.alu_op = AND;
                  I_ORI   : ctrl_i.alu_op = OR;
                  I_XORI  : ctrl_i.alu_op = XOR;
                  I_SLTI  : ctrl_i.alu_op = SLT;
                  I_SLTIU : ctrl_i.alu_op = SLTU;
                  default : ctrl_i.alu_op = ADD;
              endcase
          end

          I_SLLI: begin
              if (funct7 == 7'b0000000) begin
                  ctrl_i = '0;
                  ctrl_i.rf_write_enable = 1'b1;
                  ctrl_i.uses_rs1 = 1'b1;
                  ctrl_i.alu_src_b_select = 1'b1;
                  ctrl_i.alu_op = SLL;
              end
          end

          I_SRLI_SRAI: begin
              if ((funct7 == 7'b0000000) || (funct7 == 7'b0100000)) begin
                  ctrl_i = '0;
                  ctrl_i.rf_write_enable = 1'b1;
                  ctrl_i.uses_rs1 = 1'b1;
                  ctrl_i.alu_src_b_select = 1'b1;
                  ctrl_i.alu_op = funct7_bit5 ? SRA : SRL;
              end
          end

          I_LB,
          I_LH,
          I_LW,
          I_LBU,
          I_LHU: begin
              ctrl_i = '0;
              ctrl_i.rf_write_enable = 1'b1;
              ctrl_i.uses_rs1 = 1'b1;
              ctrl_i.alu_src_b_select = 1'b1;
              ctrl_i.mem_valid = 1'b1;
              ctrl_i.wb_src = WB_SRC_MEM;

              case (opcode_i)
                  I_LB: begin
                      ctrl_i.mem_size = BYTE;
                      ctrl_i.load_zero_extend = 1'b0;
                  end
                  I_LH: begin
                      ctrl_i.mem_size = HALF_WORD;
                      ctrl_i.load_zero_extend = 1'b0;
                  end
                  I_LW: begin
                      ctrl_i.mem_size = WORD;
                      ctrl_i.load_zero_extend = 1'b0;
                  end
                  I_LBU: begin
                      ctrl_i.mem_size = BYTE;
                      ctrl_i.load_zero_extend = 1'b1;
                  end
                  I_LHU: begin
                      ctrl_i.mem_size = HALF_WORD;
                      ctrl_i.load_zero_extend = 1'b1;
                  end
                  default: begin
                  end
              endcase
          end

          default: begin
          end
      endcase
    end

end

// --------------------------------------------------------
// S-Type Control
// --------------------------------------------------------

always_comb begin
    ctrl_s = '0;
    ctrl_s.retire_action = RETIRE_TRAP;
    ctrl_s.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;

    case (funct3)
        S_SB,
        S_SH,
        S_SW: begin
            ctrl_s = '0;
            ctrl_s.mem_valid = 1'b1;
            ctrl_s.mem_write = 1'b1;
            ctrl_s.uses_rs1 = 1'b1;
            ctrl_s.uses_rs2 = 1'b1;
            ctrl_s.alu_src_b_select = 1'b1;

            case (funct3)
                S_SB: ctrl_s.mem_size = BYTE;
                S_SH: ctrl_s.mem_size = HALF_WORD;
                S_SW: ctrl_s.mem_size = WORD;
                default: ctrl_s.mem_size = BYTE;
            endcase
        end
        default: begin
        end
    endcase
end


// --------------------------------------------------------
// B-Type Control
// --------------------------------------------------------

always_comb begin
    ctrl_b = '0;
    ctrl_b.retire_action = RETIRE_TRAP;
    ctrl_b.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;

    case (funct3)
        B_BEQ,
        B_BNE,
        B_BLT,
        B_BGE,
        B_BLTU,
        B_BGEU: begin
            ctrl_b = '0;
            ctrl_b.uses_rs1 = 1'b1;
            ctrl_b.uses_rs2 = 1'b1;
            ctrl_b.alu_src_a_select = 1'b1;
            ctrl_b.alu_src_b_select = 1'b1;
            ctrl_b.alu_op = ADD;
        end
        default: begin
        end
    endcase
end

// --------------------------------------------------------
// U-Type Control
// --------------------------------------------------------

always_comb begin
    ctrl_u = '0;

    ctrl_u.rf_write_enable = 1'b1;

    case (opcode)

        OPCODE_AUIPC: begin
            ctrl_u.alu_src_a_select = 1'b1;
            ctrl_u.alu_src_b_select = 1'b1;
        end

        OPCODE_LUI: begin
            ctrl_u.wb_src = WB_SRC_IMM;
        end

    endcase
end


// --------------------------------------------------------
// J-Type Control
// --------------------------------------------------------

always_comb begin
    ctrl_j = '0;

    ctrl_j.rf_write_enable = 1'b1;

    ctrl_j.wb_src           = WB_SRC_PC;

    ctrl_j.alu_src_a_select = 1'b1;
    ctrl_j.alu_src_b_select = 1'b1;

    ctrl_j.pc_src_select    = 1'b1;
end

// --------------------------------------------------------
// FENCE / FENCE.I Control
// --------------------------------------------------------

always_comb begin
    ctrl_misc_mem = '0;
    ctrl_misc_mem.retire_action = RETIRE_TRAP;
    ctrl_misc_mem.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;

    unique case (funct3)
        3'b000: begin
            // Blocking, in-order memory accesses already satisfy FENCE.
            ctrl_misc_mem = '0;
        end
        3'b001: begin
            ctrl_misc_mem = '0;
            ctrl_misc_mem.fence_i = 1'b1;
        end
        default: begin
        end
    endcase
end

// --------------------------------------------------------
// SYSTEM / CSR Control
// --------------------------------------------------------

always_comb begin
    ctrl_system = '0;
    ctrl_system.retire_action = RETIRE_TRAP;
    ctrl_system.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;

    if (system_type && (funct3 != 3'b000)) begin
        unique case (funct3[1:0])
            2'b01,
            2'b10,
            2'b11: begin
                ctrl_system = '0;
                ctrl_system.rf_write_enable = 1'b1;
                ctrl_system.wb_src = WB_SRC_CSR;
                ctrl_system.csr_req = 1'b1;
                ctrl_system.csr_imm_select = funct3[2];
                ctrl_system.uses_rs1 = !funct3[2];

                case (funct3[1:0])
                    2'b01: ctrl_system.csr_op = CSR_OP_RW;
                    2'b10: ctrl_system.csr_op = CSR_OP_RS;
                    2'b11: ctrl_system.csr_op = CSR_OP_RC;
                    default: ctrl_system.csr_op = CSR_OP_RW;
                endcase
            end
            default: begin
            end
        endcase
    end else if (system_type) begin
        unique case (csr_addr)
            12'h000: begin
                ctrl_system.retire_action = RETIRE_TRAP;
                ctrl_system.trap_cause = TRAP_CAUSE_ECALL_M;
            end
            12'h001: begin
                ctrl_system.retire_action = RETIRE_TRAP;
                ctrl_system.trap_cause = TRAP_CAUSE_BREAKPOINT;
            end
            12'h302: begin
                ctrl_system.retire_action = RETIRE_MRET;
            end
            12'h102: begin
                ctrl_system.retire_action = RETIRE_SRET;
            end
            default: begin
            end
        endcase
    end
end

// --------------------------------------------------------
// Final Control Selection
// --------------------------------------------------------

always_comb begin
    ctrl = '0;

    if      (r_type) ctrl = ctrl_r;
    else if (i_type) ctrl = ctrl_i;
    else if (s_type) ctrl = ctrl_s;
    else if (b_type) ctrl = ctrl_b;
    else if (u_type) ctrl = ctrl_u;
    else if (j_type) ctrl = ctrl_j;
    else if (opcode == OPCODE_MISC_MEM) ctrl = ctrl_misc_mem;
    else if (system_type) ctrl = ctrl_system;
    else begin
        ctrl.retire_action = RETIRE_TRAP;
        ctrl.trap_cause = TRAP_CAUSE_ILLEGAL_INSTRUCTION;
    end
end


// --------------------------------------------------------
// Output Assignments
// --------------------------------------------------------

assign pc_sel            = ctrl.pc_src_select;
assign op1_sel           = ctrl.alu_src_a_select;
assign op2_sel           = ctrl.alu_src_b_select;

assign alu_op            = ctrl.alu_op;

assign rf_wr_data_sel    = ctrl.wb_src;

assign dmem_req          = ctrl.mem_valid;
assign dmem_wr_en        = ctrl.mem_write;
assign dmem_size         = ctrl.mem_size;
assign dmem_zero_extend  = ctrl.load_zero_extend;

assign rf_wr_en          = ctrl.rf_write_enable;
assign uses_rs1          = ctrl.uses_rs1;
assign uses_rs2          = ctrl.uses_rs2;
assign csr_req           = ctrl.csr_req;
assign csr_op            = ctrl.csr_op;
assign csr_imm_sel       = ctrl.csr_imm_select;
assign fence_i           = ctrl.fence_i;
assign mul_div_req       = ctrl.mul_div_req;
assign mul_div_op        = ctrl.mul_div_op;
assign retire_action     = ctrl.retire_action;
assign trap_cause        = ctrl.trap_cause;

endmodule
