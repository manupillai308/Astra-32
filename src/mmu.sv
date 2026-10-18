import risc_pkg::*;

module mmu #(
  parameter int ITLB_ENTRY_COUNT = 16,
  parameter int DTLB_ENTRY_COUNT = 16
)(
  input  logic             clk,
  input  logic             reset_n,

  input  logic             imem_req,
  output logic             imem_ready,
  input  logic [31:0]      imem_virtual_addr,
  output logic             imem_resp_valid,
  output logic [31:0]      imem_rd_data,
  output logic             imem_page_fault,
  output logic [31:0]      imem_fault_addr,

  input  logic             req,
  output logic             ready,
  input  logic             wr_en,
  input  mem_size_t        size,
  input  logic [31:0]      virtual_addr,
  input  logic [31:0]      wr_data,
  input  logic             zero_extend,
  input  logic             atomic_req,
  input  atomic_op_t       atomic_op,

  input  privilege_mode_t  current_privilege,
  input  logic             mstatus_mprv,
  input  privilege_mode_t  mstatus_mpp,
  input  logic             mstatus_sum,
  input  logic             mstatus_mxr,
  input  logic [31:0]      satp,
  input  logic             clear_reservation,
  input  logic             sfence_vma_flush,

  output logic             resp_valid,
  output logic [31:0]      rd_data,
  output logic             page_fault,
  output logic [31:0]      fault_addr,

  output logic             physical_imem_req,
  input  logic             physical_imem_ready,
  output logic [31:0]      physical_imem_addr,
  input  logic             physical_imem_resp_valid,
  input  logic [31:0]      physical_imem_rd_data,

  output logic             mem_req,
  input  logic             mem_ready,
  output logic             mem_wr_en,
  output mem_size_t        mem_size,
  output logic [31:0]      mem_addr,
  output logic [31:0]      mem_wr_data,
  output logic             mem_zero_extend,
  input  logic             mem_resp_valid,
  input  logic [31:0]      mem_rd_data
);

typedef enum logic [3:0] {
  DATA_MMU_IDLE,
  DATA_MMU_TRANSLATE_REQ,
  DATA_MMU_TRANSLATE_WAIT,
  DATA_MMU_NORMAL_REQ,
  DATA_MMU_NORMAL_WAIT,
  DATA_MMU_ATOMIC_REQ,
  DATA_MMU_ATOMIC_WAIT,
  DATA_MMU_RESP
} data_mmu_state_t;

typedef enum logic [2:0] {
  IMEM_MMU_IDLE,
  IMEM_MMU_TRANSLATE_REQ,
  IMEM_MMU_TRANSLATE_WAIT,
  IMEM_MMU_PHYSICAL_REQ,
  IMEM_MMU_PHYSICAL_WAIT,
  IMEM_MMU_RESP
} imem_mmu_state_t;

data_mmu_state_t state_q;
imem_mmu_state_t imem_state_q;
logic [31:0] imem_virtual_addr_q;
logic [31:0] imem_physical_addr_q;
logic [31:0] imem_rd_data_q;
logic imem_page_fault_q;
privilege_mode_t imem_privilege_q;
logic imem_sum_q;
logic imem_mxr_q;
logic [31:0] imem_satp_q;
logic wr_en_q;
mem_size_t size_q;
logic [31:0] virtual_addr_q;
logic [31:0] physical_addr_q;
logic [31:0] wr_data_q;
logic zero_extend_q;
logic atomic_req_q;
atomic_op_t atomic_op_q;
vm_access_t access_type_q;
logic [31:0] rd_data_q;
logic page_fault_q;
privilege_mode_t dmem_privilege_q;
logic dmem_mprv_q;
privilege_mode_t dmem_mpp_q;
logic dmem_sum_q;
logic dmem_mxr_q;
logic [31:0] dmem_satp_q;

logic imem_translation_req;
logic imem_translation_ready;
logic imem_translation_resp_valid;
logic [31:0] imem_translation_physical_addr;
logic imem_translation_page_fault;
logic dmem_translation_req;
logic dmem_translation_ready;
logic dmem_translation_resp_valid;
logic [31:0] dmem_translation_physical_addr;
logic dmem_translation_page_fault;

logic normal_req;
logic normal_ready;
logic normal_resp_valid;
logic [31:0] normal_rd_data;

logic atomic_start_req;
logic atomic_ready;
logic atomic_resp_valid;
logic [31:0] atomic_result;
logic atomic_mem_req;
logic atomic_mem_ready;
logic atomic_mem_wr_en;
logic [31:0] atomic_mem_addr;
logic [31:0] atomic_mem_wr_data;
logic atomic_mem_resp_valid;
logic [31:0] atomic_mem_rd_data;
logic atomic_exclusive_active;

logic ptw_mem_req;
logic ptw_mem_ready;
logic ptw_mem_wr_en;
mem_size_t ptw_mem_size;
logic [31:0] ptw_mem_addr;
logic [31:0] ptw_mem_wr_data;
logic ptw_mem_zero_extend;
logic ptw_mem_lock;
logic ptw_mem_resp_valid;
logic [31:0] ptw_mem_rd_data;

logic arbiter_write_valid;
logic [31:0] arbiter_write_addr;

assign ready = (state_q == DATA_MMU_IDLE);
assign resp_valid = (state_q == DATA_MMU_RESP);
assign rd_data = rd_data_q;
assign page_fault = page_fault_q;
assign fault_addr = virtual_addr_q;

assign imem_ready = (imem_state_q == IMEM_MMU_IDLE);
assign imem_resp_valid = (imem_state_q == IMEM_MMU_RESP);
assign imem_rd_data = imem_rd_data_q;
assign imem_page_fault = imem_page_fault_q;
assign imem_fault_addr = imem_virtual_addr_q;
assign physical_imem_req = (imem_state_q == IMEM_MMU_PHYSICAL_REQ);
assign physical_imem_addr = imem_physical_addr_q;

assign imem_translation_req = (imem_state_q == IMEM_MMU_TRANSLATE_REQ);
assign dmem_translation_req = (state_q == DATA_MMU_TRANSLATE_REQ);
assign normal_req = (state_q == DATA_MMU_NORMAL_REQ);
assign atomic_start_req = (state_q == DATA_MMU_ATOMIC_REQ);

address_translation #(
    .ITLB_ENTRY_COUNT(ITLB_ENTRY_COUNT),
    .DTLB_ENTRY_COUNT(DTLB_ENTRY_COUNT)
) u_address_translation (
    .clk                (clk),
    .reset_n            (reset_n),
    .imem_req           (imem_translation_req),
    .imem_ready         (imem_translation_ready),
    .imem_virtual_addr  (imem_virtual_addr_q),
    .imem_privilege     (imem_privilege_q),
    .imem_sum           (imem_sum_q),
    .imem_mxr           (imem_mxr_q),
    .imem_satp          (imem_satp_q),
    .imem_resp_valid    (imem_translation_resp_valid),
    .imem_physical_addr (imem_translation_physical_addr),
    .imem_page_fault    (imem_translation_page_fault),
    .dmem_req           (dmem_translation_req),
    .dmem_ready         (dmem_translation_ready),
    .dmem_virtual_addr  (virtual_addr_q),
    .dmem_access_type   (access_type_q),
    .dmem_privilege     (dmem_privilege_q),
    .dmem_mprv          (dmem_mprv_q),
    .dmem_mpp           (dmem_mpp_q),
    .dmem_sum           (dmem_sum_q),
    .dmem_mxr           (dmem_mxr_q),
    .dmem_satp          (dmem_satp_q),
    .dmem_resp_valid    (dmem_translation_resp_valid),
    .dmem_physical_addr (dmem_translation_physical_addr),
    .dmem_page_fault    (dmem_translation_page_fault),
    .sfence_vma_flush   (sfence_vma_flush),
    .mem_req            (ptw_mem_req),
    .mem_ready          (ptw_mem_ready),
    .mem_wr_en          (ptw_mem_wr_en),
    .mem_size           (ptw_mem_size),
    .mem_addr           (ptw_mem_addr),
    .mem_wr_data        (ptw_mem_wr_data),
    .mem_zero_extend    (ptw_mem_zero_extend),
    .mem_lock           (ptw_mem_lock),
    .mem_resp_valid     (ptw_mem_resp_valid),
    .mem_rd_data        (ptw_mem_rd_data)
);

atomic_unit u_atomic_unit (
    .clk                  (clk),
    .reset_n              (reset_n),
    .req                  (atomic_start_req),
    .ready                (atomic_ready),
    .op                   (atomic_op_q),
    .addr                 (physical_addr_q),
    .operand              (wr_data_q),
    .resp_valid           (atomic_resp_valid),
    .result               (atomic_result),
    .mem_req              (atomic_mem_req),
    .mem_wr_en            (atomic_mem_wr_en),
    .mem_addr             (atomic_mem_addr),
    .mem_wr_data          (atomic_mem_wr_data),
    .mem_ready            (atomic_mem_ready),
    .mem_resp_valid       (atomic_mem_resp_valid),
    .mem_rd_data          (atomic_mem_rd_data),
    .clear_reservation    (clear_reservation),
    .local_write_valid    (arbiter_write_valid),
    .local_write_addr     (arbiter_write_addr),
    .external_write_valid (1'b0),
    .external_write_addr  (32'h0),
    .exclusive_active     (atomic_exclusive_active)
);

memory_arbiter u_memory_arbiter (
    .clk                (clk),
    .reset_n            (reset_n),
    .normal_req         (normal_req),
    .normal_ready       (normal_ready),
    .normal_wr_en       (wr_en_q),
    .normal_size        (size_q),
    .normal_addr        (physical_addr_q),
    .normal_wr_data     (wr_data_q),
    .normal_zero_extend (zero_extend_q),
    .normal_lock        (1'b0),
    .normal_resp_valid  (normal_resp_valid),
    .normal_rd_data     (normal_rd_data),
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
    .ptw_req            (ptw_mem_req),
    .ptw_ready          (ptw_mem_ready),
    .ptw_wr_en          (ptw_mem_wr_en),
    .ptw_size           (ptw_mem_size),
    .ptw_addr           (ptw_mem_addr),
    .ptw_wr_data        (ptw_mem_wr_data),
    .ptw_zero_extend    (ptw_mem_zero_extend),
    .ptw_lock           (ptw_mem_lock),
    .ptw_resp_valid     (ptw_mem_resp_valid),
    .ptw_rd_data        (ptw_mem_rd_data),
    .mem_req            (mem_req),
    .mem_ready          (mem_ready),
    .mem_wr_en          (mem_wr_en),
    .mem_size           (mem_size),
    .mem_addr           (mem_addr),
    .mem_wr_data        (mem_wr_data),
    .mem_zero_extend    (mem_zero_extend),
    .mem_resp_valid     (mem_resp_valid),
    .mem_rd_data        (mem_rd_data),
    .write_valid        (arbiter_write_valid),
    .write_addr         (arbiter_write_addr)
);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    imem_state_q <= IMEM_MMU_IDLE;
    imem_virtual_addr_q <= 32'h0;
    imem_physical_addr_q <= 32'h0;
    imem_rd_data_q <= 32'h0;
    imem_page_fault_q <= 1'b0;
    imem_privilege_q <= PRIVILEGE_M;
    imem_sum_q <= 1'b0;
    imem_mxr_q <= 1'b0;
    imem_satp_q <= 32'h0;
  end else begin
    unique case (imem_state_q)
      IMEM_MMU_IDLE: begin
        if (imem_req) begin
          imem_virtual_addr_q <= imem_virtual_addr;
          imem_page_fault_q <= 1'b0;
          imem_privilege_q <= current_privilege;
          imem_sum_q <= mstatus_sum;
          imem_mxr_q <= mstatus_mxr;
          imem_satp_q <= satp;
          imem_state_q <= IMEM_MMU_TRANSLATE_REQ;
        end
      end

      IMEM_MMU_TRANSLATE_REQ: begin
        if (imem_translation_ready) imem_state_q <= IMEM_MMU_TRANSLATE_WAIT;
      end

      IMEM_MMU_TRANSLATE_WAIT: begin
        if (imem_translation_resp_valid) begin
          imem_physical_addr_q <= imem_translation_physical_addr;
          if (imem_translation_page_fault) begin
            imem_page_fault_q <= 1'b1;
            imem_rd_data_q <= 32'h0;
            imem_state_q <= IMEM_MMU_RESP;
          end else begin
            imem_state_q <= IMEM_MMU_PHYSICAL_REQ;
          end
        end
      end

      IMEM_MMU_PHYSICAL_REQ: begin
        if (physical_imem_ready) begin
          imem_state_q <= IMEM_MMU_PHYSICAL_WAIT;
        end
      end

      IMEM_MMU_PHYSICAL_WAIT: begin
        if (physical_imem_resp_valid) begin
          imem_rd_data_q <= physical_imem_rd_data;
          imem_state_q <= IMEM_MMU_RESP;
        end
      end

      IMEM_MMU_RESP: imem_state_q <= IMEM_MMU_IDLE;
      default: imem_state_q <= IMEM_MMU_IDLE;
    endcase
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    state_q <= DATA_MMU_IDLE;
    wr_en_q <= 1'b0;
    size_q <= WORD;
    virtual_addr_q <= 32'h0;
    physical_addr_q <= 32'h0;
    wr_data_q <= 32'h0;
    zero_extend_q <= 1'b0;
    atomic_req_q <= 1'b0;
    atomic_op_q <= ATOMIC_LR;
    access_type_q <= VM_ACCESS_LOAD;
    rd_data_q <= 32'h0;
    page_fault_q <= 1'b0;
    dmem_privilege_q <= PRIVILEGE_M;
    dmem_mprv_q <= 1'b0;
    dmem_mpp_q <= PRIVILEGE_M;
    dmem_sum_q <= 1'b0;
    dmem_mxr_q <= 1'b0;
    dmem_satp_q <= 32'h0;
  end else begin
    unique case (state_q)
      DATA_MMU_IDLE: begin
        if (req) begin
          wr_en_q <= wr_en;
          size_q <= size;
          virtual_addr_q <= virtual_addr;
          wr_data_q <= wr_data;
          zero_extend_q <= zero_extend;
          atomic_req_q <= atomic_req;
          atomic_op_q <= atomic_op;
          page_fault_q <= 1'b0;
          dmem_privilege_q <= current_privilege;
          dmem_mprv_q <= mstatus_mprv;
          dmem_mpp_q <= mstatus_mpp;
          dmem_sum_q <= mstatus_sum;
          dmem_mxr_q <= mstatus_mxr;
          dmem_satp_q <= satp;

          if (atomic_req && (atomic_op == ATOMIC_LR)) begin
            access_type_q <= VM_ACCESS_LOAD;
          end else if (wr_en || atomic_req) begin
            access_type_q <= VM_ACCESS_STORE;
          end else begin
            access_type_q <= VM_ACCESS_LOAD;
          end

          state_q <= DATA_MMU_TRANSLATE_REQ;
        end
      end

      DATA_MMU_TRANSLATE_REQ: begin
        if (dmem_translation_ready) state_q <= DATA_MMU_TRANSLATE_WAIT;
      end

      DATA_MMU_TRANSLATE_WAIT: begin
        if (dmem_translation_resp_valid) begin
          physical_addr_q <= dmem_translation_physical_addr;
          if (dmem_translation_page_fault) begin
            page_fault_q <= 1'b1;
            rd_data_q <= 32'h0;
            state_q <= DATA_MMU_RESP;
          end else begin
            state_q <= atomic_req_q ? DATA_MMU_ATOMIC_REQ :
                                      DATA_MMU_NORMAL_REQ;
          end
        end
      end

      DATA_MMU_NORMAL_REQ: begin
        if (normal_ready) begin
          if (normal_resp_valid) begin
            rd_data_q <= normal_rd_data;
            state_q <= DATA_MMU_RESP;
          end else begin
            state_q <= DATA_MMU_NORMAL_WAIT;
          end
        end
      end

      DATA_MMU_NORMAL_WAIT: begin
        if (normal_resp_valid) begin
          rd_data_q <= normal_rd_data;
          state_q <= DATA_MMU_RESP;
        end
      end

      DATA_MMU_ATOMIC_REQ: begin
        if (atomic_ready) state_q <= DATA_MMU_ATOMIC_WAIT;
      end

      DATA_MMU_ATOMIC_WAIT: begin
        if (atomic_resp_valid) begin
          rd_data_q <= atomic_result;
          state_q <= DATA_MMU_RESP;
        end
      end

      DATA_MMU_RESP: state_q <= DATA_MMU_IDLE;
      default: state_q <= DATA_MMU_IDLE;
    endcase
  end
end

endmodule
