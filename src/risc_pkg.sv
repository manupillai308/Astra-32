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
  OPCODE_JAL = 7'h6F
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
// R-Type Instructions (Funct7[5], Funct3)
// --------------------------------------------------------

typedef enum logic [3:0] { 
  R_ADD = 4'h0,
  R_SUB = 4'h8,
  R_SLL = 4'h1,
  R_SLT = 4'h2,
  R_SLTU = 4'h3,
  R_XOR = 4'h4,
  R_SRL = 4'h5,
  R_SRA = 4'hD,
  R_OR = 4'h6,
  R_AND = 4'h7
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

typedef enum logic [1:0] {
    WB_SRC_ALU = 2'b00,
    WB_SRC_MEM = 2'b01,
    WB_SRC_IMM = 2'b10,
    WB_SRC_PC  = 2'b11
} wb_src_t;


// --------------------------------------------------------
// Control Signal Struct
// --------------------------------------------------------

typedef struct packed {
    logic      mem_valid;           // Asserted for memory access
    logic      mem_write;           // 1 = write, 0 = read
    mem_size_t mem_size;            // BYTE, HALF_WORD, WORD
    logic      load_zero_extend;    // 1 = zero-extend loads (LBU/LHU)

    logic      rf_write_enable;     // Register file write enable

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
typedef struct packed {
    logic        valid;
    logic [31:0] pc;                // for AUIPC / branch target
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;
    logic [31:0] rs1_data;
    logic [31:0] rs2_data;
    logic [31:0] immediate;
    logic [4:0]  rd_addr;
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
} id_ex_t;

// EX/MEM: ALU result + resolved branch + remaining MEM/WB controls
typedef struct packed {
    logic        valid;
    logic [31:0] alu_res;
    logic [31:0] rs2_data;          // for stores
    logic [31:0] immediate;         // for LUI WB
    logic [31:0] next_seq_pc;       // for JAL/JALR WB (= pc + 4)
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
    wb_src_t     rf_wr_data_sel;
} ex_mem_t;

// MEM/WB: writeback inputs. dmem_rd_data is taken straight off the
// dmem output reg during the WB cycle (not stored here).
typedef struct packed {
    logic        valid;
    logic [31:0] alu_res;
    logic [31:0] immediate;
    logic [31:0] next_seq_pc;
    logic [4:0]  rd_addr;
    logic        rf_wr_en;
    wb_src_t     rf_wr_data_sel;
} mem_wb_t;


endpackage

