// --------------------------------------------------------
// RISC-V RV32I Processor Package
// --------------------------------------------------------
package risc_pkg;

// --------------------------------------------------------
// RISC-V Opcodes (Instruction Formats)
// --------------------------------------------------------

typedef enum logic [6:0] { 
  OPCODE_R_TYPE = 7'h33,
  OPCODE_I_LOAD = 7'h03,
  OPCODE_I_ALU = 7'h13,
  OPCODE_I_JALR = 7'h67,
  OPCODE_S_TYPE = 7'h23,
  OPCODE_B_TYPE = 7'h63,
  OPCODE_LUI = 7'h37,
  OPCODE_AUIPC = 7'h17,
  OPCODE_JAL = 7'h6F,
  OPCODE_SYSTEM = 7'h73
 } opcode_t;




// --------------------------------------------------------
// ALU Operation Selector
// --------------------------------------------------------

typedef enum logic [3:0] { 
  ADD,
  SUB,
  SLL,
  SLT,
  SLTU,
  XOR,
  SRL,
  SRA,
  OR,
  AND
 } alu_op_t;



// --------------------------------------------------------
// Memory Access Sizes
// --------------------------------------------------------

typedef enum logic [1:0] { 
  BYTE = 2'b00,
  HALF_WORD = 2'b01,
  WORD = 2'b11
 } mem_size_t;




// --------------------------------------------------------
// B-Type Instructions (Funct3)
// --------------------------------------------------------

typedef enum logic [2:0] { 
  B_BEQ = 3'h0,
  B_BNE = 3'h1,
  B_BLT = 3'h4,
  B_BGE = 3'h5,
  B_BLTU = 3'h6,
  B_BGEU = 3'h7
 } b_type_instr_t;



// --------------------------------------------------------
// R-Type Instructions (Funct7, Funct3)
// --------------------------------------------------------

typedef enum logic [9:0] {
  R_ADD  = {7'b0000000, 3'b000},
  R_SUB  = {7'b0100000, 3'b000},
  R_SLL  = {7'b0000000, 3'b001},
  R_SLT  = {7'b0000000, 3'b010},
  R_SLTU = {7'b0000000, 3'b011},
  R_XOR  = {7'b0000000, 3'b100},
  R_SRL  = {7'b0000000, 3'b101},
  R_SRA  = {7'b0100000, 3'b101},
  R_OR   = {7'b0000000, 3'b110},
  R_AND  = {7'b0000000, 3'b111}
 } r_type_instr_t;




// --------------------------------------------------------
// I-Type Instructions (Opcode[4], Funct3)
// --------------------------------------------------------


typedef enum logic [3:0] {
    I_LB        = 4'h0,
    I_LH        = 4'h1,
    I_LW        = 4'h2,
    I_LBU       = 4'h4,
    I_LHU       = 4'h5,
    I_ADDI      = 4'h8,
    I_SLTI      = 4'hA,
    I_SLTIU     = 4'hB,
    I_XORI      = 4'hC,
    I_ORI       = 4'hE,
    I_ANDI      = 4'hF,
    I_SLLI      = 4'h9,
    I_SRLI_SRAI = 4'hD  // shared funct3
} i_type_instr_t;


// --------------------------------------------------------
// S-Type Instructions (Funct3)
// --------------------------------------------------------

typedef enum logic [2:0] {
    S_SB = 3'h0,
    S_SH = 3'h1,
    S_SW = 3'h2
} s_type_instr_t;


// --------------------------------------------------------
// Register File Writeback Sources
// --------------------------------------------------------

typedef enum logic [2:0] {
    WB_SRC_ALU = 3'b000,
    WB_SRC_MEM = 3'b001,
    WB_SRC_IMM = 3'b010,
    WB_SRC_PC  = 3'b011,
    WB_SRC_CSR = 3'b100
} wb_src_t;

typedef enum logic [1:0] {
    CSR_OP_RW = 2'b00,
    CSR_OP_RS = 2'b01,
    CSR_OP_RC = 2'b10
} csr_op_t;

typedef enum logic [3:0] {
    TRAP_CAUSE_INST_ADDR_MISALIGNED  = 4'd0,
    TRAP_CAUSE_ILLEGAL_INSTRUCTION   = 4'd2,
    TRAP_CAUSE_BREAKPOINT            = 4'd3,
    TRAP_CAUSE_LOAD_ADDR_MISALIGNED  = 4'd4,
    TRAP_CAUSE_STORE_ADDR_MISALIGNED = 4'd6,
    TRAP_CAUSE_ECALL_M               = 4'd11
} trap_cause_t;

typedef struct packed {
    logic [31:0] mepc;
    logic [31:0] mcause;
    logic [31:0] mtval;
} trap_payload_t;

typedef enum logic [1:0] {
    RETIRE_NORMAL = 2'b00,
    RETIRE_TRAP   = 2'b01,
    RETIRE_MRET   = 2'b10
} retire_action_t;


// --------------------------------------------------------
// Control Signal Struct
// --------------------------------------------------------

typedef struct packed {
    logic      mem_valid;           // Asserted for memory access
    logic      mem_write;           // 1 = write, 0 = read
    mem_size_t mem_size;            // BYTE, HALF_WORD, WORD
    logic      load_zero_extend;    // 1 = zero-extend loads (LBU/LHU)

    logic      rf_write_enable;     // Register file write enable
    logic      uses_rs1;            // Instruction consumes rs1 as a GPR
    logic      uses_rs2;            // Instruction consumes rs2 as a GPR

    logic      csr_req;             // CSR instruction
    csr_op_t   csr_op;              // RW/RS/RC operation
    logic      csr_imm_select;      // 1 = use zimm, 0 = use rs1 data

    retire_action_t retire_action;  // Normal retire, trap entry, or mret
    trap_cause_t trap_cause;        // Decode-stage exception cause

    logic      pc_src_select;       // 1 = branch/jump, 0 = sequential

    logic      alu_src_a_select;    // 1 = PC, 0 = rs1
    logic      alu_src_b_select;    // 1 = IMM, 0 = rs2

    wb_src_t   wb_src;              // Writeback data source

    alu_op_t   alu_op;              // ALU function selector
} control_t;


// --------------------------------------------------------
// Pipeline Register Structs
//   Each stage's outputs are latched into the next pipeline
//   register on posedge. `valid` is 1 when the slot holds a
//   real instruction, 0 for a bubble. Side effects (regfile
//   write, dmem write, branch redirect) are gated by `valid`.
// --------------------------------------------------------

// ID/EX: decoded instruction + read register values + control
typedef enum logic [1:0] {
  FWD_RF,
  FWD_EXMEM,
  FWD_MEMWB
} fwd_flag_t;

typedef struct packed {
    logic        valid;
    logic [31:0] pc;                // for AUIPC / branch target
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] immediate;
    logic [4:0]  rs1_addr;
    logic [4:0]  rd_addr;
    logic        uses_rs1;
    logic        uses_rs2;
    // ALU controls
    logic        op1_sel;
    logic        op2_sel;
    alu_op_t     alu_op;
    // Branch / jump
    logic        is_b_type;
    logic [2:0]  funct3;
    logic        pc_sel;            // unconditional jump (JAL/JALR)
    // MEM controls
    logic        dmem_req;
    logic        dmem_wr_en;
    mem_size_t   dmem_size;
    logic        dmem_zero_extend;
    // WB controls
    logic        rf_wr_en;
    wb_src_t     rf_wr_data_sel;
    logic        csr_req;
    logic [11:0] csr_addr;
    csr_op_t     csr_op;
    logic        csr_imm_sel;
    logic [31:0] csr_old_data;
    retire_action_t retire_action;
    trap_payload_t trap;
    fwd_flag_t   fwd_a_sel;
    fwd_flag_t   fwd_b_sel;
    logic        load_from_memory;
} id_ex_t;

// EX/MEM: ALU result + resolved branch + remaining MEM/WB controls
typedef struct packed {
    logic        valid;
    logic [31:0] alu_res;
    logic [31:0] rs2_data;          // for stores
    logic [31:0] branch_target;     // {alu_res[31:1], 1'b0}
    logic [4:0]  rd_addr;
    // Resolved branch
    logic        branch_taken;      // from branch_control
    logic        pc_sel;            // unconditional jump
    // MEM controls
    logic        dmem_req;
    logic        dmem_wr_en;
    mem_size_t   dmem_size;
    logic        dmem_zero_extend;
    // WB controls
    logic        rf_wr_en;
    logic [31:0] forward_data;
    logic        load_from_memory;
    logic        csr_wr_en;
    logic [11:0] csr_addr;
    logic [31:0] csr_wr_data;
    retire_action_t retire_action;
    trap_payload_t trap;
} ex_mem_t;

// MEM/WB: writeback inputs. dmem_rd_data is taken straight off the
// dmem output reg during the WB cycle (not stored here).
typedef struct packed {
    logic        valid;
    logic [4:0]  rd_addr;
    logic        rf_wr_en;
    logic [31:0] wb_data;
    logic        csr_wr_en;
    logic [11:0] csr_addr;
    logic [31:0] csr_wr_data;
    retire_action_t retire_action;
    trap_payload_t trap;
} mem_wb_t;

endpackage

