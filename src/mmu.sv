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
  DATA_MMU_TLB_REQ,
  DATA_MMU_TLB_WAIT,
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
  IMEM_MMU_TLB_REQ,
  IMEM_MMU_TLB_WAIT,
  IMEM_MMU_TRANSLATE_REQ,
  IMEM_MMU_TRANSLATE_WAIT,
  IMEM_MMU_PHYSICAL_REQ,
  IMEM_MMU_PHYSICAL_WAIT,
  IMEM_MMU_RESP
} imem_mmu_state_t;

typedef enum logic [1:0] {
  TRANSLATION_OWNER_NONE,
  TRANSLATION_OWNER_IMEM,
  TRANSLATION_OWNER_DMEM
} translation_owner_t;

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

translation_owner_t translation_owner_q;
translation_owner_t translation_selected_owner;
translation_owner_t translation_next_priority_q;
logic translation_selected_valid;
logic translation_req;
logic translation_ready;
logic translation_resp_valid;
logic [31:0] translation_virtual_addr;
vm_access_t translation_access_type;
privilege_mode_t translation_current_privilege;
logic translation_mprv;
privilege_mode_t translation_mpp;
logic translation_sum;
logic translation_mxr;
logic [31:0] translation_satp;
logic translation_page_fault;
tlb_fill_t translation_fill;

logic itlb_req;
logic itlb_ready;
logic itlb_resp_valid;
logic itlb_hit;
logic [31:0] itlb_physical_addr;
logic itlb_page_fault;
logic itlb_fill_valid;
logic dtlb_req;
logic dtlb_ready;
logic dtlb_resp_valid;
logic dtlb_hit;
logic [31:0] dtlb_physical_addr;
logic dtlb_page_fault;
logic dtlb_fill_valid;
logic imem_translation_enabled;
logic dmem_translation_enabled;
privilege_mode_t dmem_effective_privilege;

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

always_comb begin
  dmem_effective_privilege = dmem_privilege_q;
  if ((dmem_privilege_q == PRIVILEGE_M) && dmem_mprv_q) begin
    dmem_effective_privilege = dmem_mpp_q;
  end
end

assign imem_translation_enabled = imem_satp_q[31] &&
                                  (imem_privilege_q != PRIVILEGE_M);
assign dmem_translation_enabled = dmem_satp_q[31] &&
                                  (dmem_effective_privilege != PRIVILEGE_M);
assign itlb_req = (imem_state_q == IMEM_MMU_TLB_REQ) &&
                  imem_translation_enabled;
assign dtlb_req = (state_q == DATA_MMU_TLB_REQ) &&
                  dmem_translation_enabled;
assign imem_translation_req = (imem_state_q == IMEM_MMU_TRANSLATE_REQ);
assign dmem_translation_req = (state_q == DATA_MMU_TRANSLATE_REQ);
assign normal_req = (state_q == DATA_MMU_NORMAL_REQ);
assign atomic_start_req = (state_q == DATA_MMU_ATOMIC_REQ);

assign itlb_fill_valid = imem_translation_resp_valid &&
                         !imem_translation_page_fault;
assign dtlb_fill_valid = dmem_translation_resp_valid &&
                         !dmem_translation_page_fault;

// Separate I/D TLBs share the existing translation arbiter and page walker.
sv32_tlb #(
    .ENTRY_COUNT(ITLB_ENTRY_COUNT)
) u_itlb (
    .clk                (clk),
    .reset_n            (reset_n),
    .req                (itlb_req),
    .ready              (itlb_ready),
    .virtual_addr       (imem_virtual_addr_q),
    .asid               (imem_satp_q[30:22]),
    .access_type        (VM_ACCESS_INSTRUCTION),
    .privilege          (imem_privilege_q),
    .sum                (imem_sum_q),
    .mxr                (imem_mxr_q),
    .resp_valid         (itlb_resp_valid),
    .hit                (itlb_hit),
    .physical_addr      (itlb_physical_addr),
    .page_fault         (itlb_page_fault),
    .fill_valid         (itlb_fill_valid),
    .fill_virtual_addr  (imem_virtual_addr_q),
    .fill_asid          (imem_satp_q[30:22]),
    .fill               (translation_fill),
    .flush              (sfence_vma_flush)
);

sv32_tlb #(
    .ENTRY_COUNT(DTLB_ENTRY_COUNT)
) u_dtlb (
    .clk                (clk),
    .reset_n            (reset_n),
    .req                (dtlb_req),
    .ready              (dtlb_ready),
    .virtual_addr       (virtual_addr_q),
    .asid               (dmem_satp_q[30:22]),
    .access_type        (access_type_q),
    .privilege          (dmem_effective_privilege),
    .sum                (dmem_sum_q),
    .mxr                (dmem_mxr_q),
    .resp_valid         (dtlb_resp_valid),
    .hit                (dtlb_hit),
    .physical_addr      (dtlb_physical_addr),
    .page_fault         (dtlb_page_fault),
    .fill_valid         (dtlb_fill_valid),
    .fill_virtual_addr  (virtual_addr_q),
    .fill_asid          (dmem_satp_q[30:22]),
    .fill               (translation_fill),
    .flush              (sfence_vma_flush)
);

always_comb begin
  translation_selected_owner = TRANSLATION_OWNER_NONE;
  translation_selected_valid = 1'b0;

  if (translation_next_priority_q == TRANSLATION_OWNER_IMEM) begin
    if (imem_translation_req) begin
      translation_selected_owner = TRANSLATION_OWNER_IMEM;
      translation_selected_valid = 1'b1;
    end else if (dmem_translation_req) begin
      translation_selected_owner = TRANSLATION_OWNER_DMEM;
      translation_selected_valid = 1'b1;
    end
  end else begin
    if (dmem_translation_req) begin
      translation_selected_owner = TRANSLATION_OWNER_DMEM;
      translation_selected_valid = 1'b1;
    end else if (imem_translation_req) begin
      translation_selected_owner = TRANSLATION_OWNER_IMEM;
      translation_selected_valid = 1'b1;
    end
  end
end

always_comb begin
  translation_req = translation_selected_valid;
  translation_virtual_addr = 32'h0;
  translation_access_type = VM_ACCESS_INSTRUCTION;
  translation_current_privilege = PRIVILEGE_M;
  translation_mprv = 1'b0;
  translation_mpp = PRIVILEGE_M;
  translation_sum = 1'b0;
  translation_mxr = 1'b0;
  translation_satp = 32'h0;
  imem_translation_ready = 1'b0;
  dmem_translation_ready = 1'b0;

  unique case (translation_selected_owner)
    TRANSLATION_OWNER_IMEM: begin
      translation_virtual_addr = imem_virtual_addr_q;
      translation_current_privilege = imem_privilege_q;
      translation_sum = imem_sum_q;
      translation_mxr = imem_mxr_q;
      translation_satp = imem_satp_q;
      imem_translation_ready = translation_ready;
    end
    TRANSLATION_OWNER_DMEM: begin
      translation_virtual_addr = virtual_addr_q;
      translation_access_type = access_type_q;
      translation_current_privilege = dmem_privilege_q;
      translation_mprv = dmem_mprv_q;
      translation_mpp = dmem_mpp_q;
      translation_sum = dmem_sum_q;
      translation_mxr = dmem_mxr_q;
      translation_satp = dmem_satp_q;
      dmem_translation_ready = translation_ready;
    end
    default: begin
    end
  endcase
end

assign imem_translation_resp_valid = translation_resp_valid &&
                                     (translation_owner_q == TRANSLATION_OWNER_IMEM);
assign dmem_translation_resp_valid = translation_resp_valid &&
                                     (translation_owner_q == TRANSLATION_OWNER_DMEM);
assign imem_translation_physical_addr = translation_fill.physical_addr;
assign dmem_translation_physical_addr = translation_fill.physical_addr;
assign imem_translation_page_fault = translation_page_fault;
assign dmem_translation_page_fault = translation_page_fault;

data_translation u_data_translation (
    .clk               (clk),
    .reset_n           (reset_n),
    .req               (translation_req),
    .ready             (translation_ready),
    .virtual_addr      (translation_virtual_addr),
    .access_type       (translation_access_type),
    .current_privilege (translation_current_privilege),
    .mstatus_mprv      (translation_mprv),
    .mstatus_mpp       (translation_mpp),
    .mstatus_sum       (translation_sum),
    .mstatus_mxr       (translation_mxr),
    .satp              (translation_satp),
    .resp_valid        (translation_resp_valid),
    .page_fault        (translation_page_fault),
    .fill              (translation_fill),
    .mem_req           (ptw_mem_req),
    .mem_ready         (ptw_mem_ready),
    .mem_wr_en         (ptw_mem_wr_en),
    .mem_size          (ptw_mem_size),
    .mem_addr          (ptw_mem_addr),
    .mem_wr_data       (ptw_mem_wr_data),
    .mem_zero_extend   (ptw_mem_zero_extend),
    .mem_lock          (ptw_mem_lock),
    .mem_resp_valid    (ptw_mem_resp_valid),
    .mem_rd_data       (ptw_mem_rd_data)
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
    translation_owner_q <= TRANSLATION_OWNER_NONE;
    translation_next_priority_q <= TRANSLATION_OWNER_IMEM;
  end else if (translation_req && translation_ready) begin
    translation_owner_q <= translation_selected_owner;
    translation_next_priority_q <=
        (translation_selected_owner == TRANSLATION_OWNER_IMEM) ?
        TRANSLATION_OWNER_DMEM : TRANSLATION_OWNER_IMEM;
  end
end

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
          imem_state_q <= IMEM_MMU_TLB_REQ;
        end
      end

      IMEM_MMU_TLB_REQ: begin
        if (!imem_translation_enabled) begin
          imem_physical_addr_q <= imem_virtual_addr_q;
          imem_state_q <= IMEM_MMU_PHYSICAL_REQ;
        end else if (itlb_ready) begin
          imem_state_q <= IMEM_MMU_TLB_WAIT;
        end
      end

      IMEM_MMU_TLB_WAIT: begin
        if (itlb_resp_valid) begin
          if (itlb_hit) begin
            imem_physical_addr_q <= itlb_physical_addr;
            if (itlb_page_fault) begin
              imem_page_fault_q <= 1'b1;
              imem_rd_data_q <= 32'h0;
              imem_state_q <= IMEM_MMU_RESP;
            end else begin
              imem_state_q <= IMEM_MMU_PHYSICAL_REQ;
            end
          end else begin
            imem_state_q <= IMEM_MMU_TRANSLATE_REQ;
          end
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

          state_q <= DATA_MMU_TLB_REQ;
        end
      end

      DATA_MMU_TLB_REQ: begin
        if (!dmem_translation_enabled) begin
          physical_addr_q <= virtual_addr_q;
          state_q <= atomic_req_q ? DATA_MMU_ATOMIC_REQ :
                                    DATA_MMU_NORMAL_REQ;
        end else if (dtlb_ready) begin
          state_q <= DATA_MMU_TLB_WAIT;
        end
      end

      DATA_MMU_TLB_WAIT: begin
        if (dtlb_resp_valid) begin
          if (dtlb_hit) begin
            physical_addr_q <= dtlb_physical_addr;
            if (dtlb_page_fault) begin
              page_fault_q <= 1'b1;
              rd_data_q <= 32'h0;
              state_q <= DATA_MMU_RESP;
            end else begin
              state_q <= atomic_req_q ? DATA_MMU_ATOMIC_REQ :
                                        DATA_MMU_NORMAL_REQ;
            end
          end else begin
            state_q <= DATA_MMU_TRANSLATE_REQ;
          end
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
