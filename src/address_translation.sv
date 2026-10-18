import risc_pkg::*;

module address_translation #(
  parameter int ITLB_ENTRY_COUNT = 16,
  parameter int DTLB_ENTRY_COUNT = 16
)(
  input  logic             clk,
  input  logic             reset_n,

  input  logic             imem_req,
  output logic             imem_ready,
  input  logic [31:0]      imem_virtual_addr,
  input  privilege_mode_t  imem_privilege,
  input  logic             imem_sum,
  input  logic             imem_mxr,
  input  logic [31:0]      imem_satp,
  output logic             imem_resp_valid,
  output logic [31:0]      imem_physical_addr,
  output logic             imem_page_fault,

  input  logic             dmem_req,
  output logic             dmem_ready,
  input  logic [31:0]      dmem_virtual_addr,
  input  vm_access_t       dmem_access_type,
  input  privilege_mode_t  dmem_privilege,
  input  logic             dmem_mprv,
  input  privilege_mode_t  dmem_mpp,
  input  logic             dmem_sum,
  input  logic             dmem_mxr,
  input  logic [31:0]      dmem_satp,
  output logic             dmem_resp_valid,
  output logic [31:0]      dmem_physical_addr,
  output logic             dmem_page_fault,

  input  logic             sfence_vma_flush,

  output logic             mem_req,
  input  logic             mem_ready,
  output logic             mem_wr_en,
  output mem_size_t        mem_size,
  output logic [31:0]      mem_addr,
  output logic [31:0]      mem_wr_data,
  output logic             mem_zero_extend,
  output logic             mem_lock,
  input  logic             mem_resp_valid,
  input  logic [31:0]      mem_rd_data
);

typedef enum logic [2:0] {
  TRANSLATE_IDLE,
  TRANSLATE_TLB_REQ,
  TRANSLATE_TLB_WAIT,
  TRANSLATE_WALK_REQ,
  TRANSLATE_WALK_WAIT,
  TRANSLATE_RESP
} translate_state_t;

typedef enum logic [1:0] {
  WALK_OWNER_NONE,
  WALK_OWNER_IMEM,
  WALK_OWNER_DMEM
} walk_owner_t;

translate_state_t imem_state_q;
translate_state_t dmem_state_q;
logic [31:0] imem_virtual_addr_q;
privilege_mode_t imem_privilege_q;
logic imem_sum_q;
logic imem_mxr_q;
logic [31:0] imem_satp_q;
logic [31:0] imem_physical_addr_q;
logic imem_page_fault_q;
logic [31:0] dmem_virtual_addr_q;
vm_access_t dmem_access_type_q;
privilege_mode_t dmem_effective_privilege_q;
logic dmem_sum_q;
logic dmem_mxr_q;
logic [31:0] dmem_satp_q;
logic [31:0] dmem_physical_addr_q;
logic dmem_page_fault_q;

privilege_mode_t dmem_effective_privilege;
logic imem_translation_enabled;
logic dmem_translation_enabled;

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

walk_owner_t walk_owner_q;
walk_owner_t walk_selected_owner;
walk_owner_t walk_next_priority_q;
logic walk_selected_valid;
logic walker_req;
logic walker_ready;
logic walker_resp_valid;
logic walker_page_fault;
tlb_fill_t walker_fill;
logic [31:0] walker_virtual_addr;
vm_access_t walker_access_type;
privilege_mode_t walker_privilege;
logic [21:0] walker_root_ppn;
logic walker_sum;
logic walker_mxr;

always_comb begin
  dmem_effective_privilege = dmem_privilege;
  if ((dmem_privilege == PRIVILEGE_M) && dmem_mprv) begin
    dmem_effective_privilege = dmem_mpp;
  end
end

assign imem_ready = (imem_state_q == TRANSLATE_IDLE);
assign imem_resp_valid = (imem_state_q == TRANSLATE_RESP);
assign imem_physical_addr = imem_physical_addr_q;
assign imem_page_fault = imem_page_fault_q;
assign dmem_ready = (dmem_state_q == TRANSLATE_IDLE);
assign dmem_resp_valid = (dmem_state_q == TRANSLATE_RESP);
assign dmem_physical_addr = dmem_physical_addr_q;
assign dmem_page_fault = dmem_page_fault_q;

assign imem_translation_enabled = imem_satp_q[31] &&
                                  (imem_privilege_q != PRIVILEGE_M);
assign dmem_translation_enabled = dmem_satp_q[31] &&
                                  (dmem_effective_privilege_q != PRIVILEGE_M);
assign itlb_req = (imem_state_q == TRANSLATE_TLB_REQ) &&
                  imem_translation_enabled;
assign dtlb_req = (dmem_state_q == TRANSLATE_TLB_REQ) &&
                  dmem_translation_enabled;
assign itlb_fill_valid = walker_resp_valid && !walker_page_fault &&
                         (walk_owner_q == WALK_OWNER_IMEM);
assign dtlb_fill_valid = walker_resp_valid && !walker_page_fault &&
                         (walk_owner_q == WALK_OWNER_DMEM);

sv32_tlb #(
    .ENTRY_COUNT(ITLB_ENTRY_COUNT)
) u_itlb (
    .clk               (clk),
    .reset_n           (reset_n),
    .req               (itlb_req),
    .ready             (itlb_ready),
    .virtual_addr      (imem_virtual_addr_q),
    .asid              (imem_satp_q[30:22]),
    .access_type       (VM_ACCESS_INSTRUCTION),
    .privilege         (imem_privilege_q),
    .sum               (imem_sum_q),
    .mxr               (imem_mxr_q),
    .resp_valid        (itlb_resp_valid),
    .hit               (itlb_hit),
    .physical_addr     (itlb_physical_addr),
    .page_fault        (itlb_page_fault),
    .fill_valid        (itlb_fill_valid),
    .fill_virtual_addr (imem_virtual_addr_q),
    .fill_asid         (imem_satp_q[30:22]),
    .fill              (walker_fill),
    .flush             (sfence_vma_flush)
);

sv32_tlb #(
    .ENTRY_COUNT(DTLB_ENTRY_COUNT)
) u_dtlb (
    .clk               (clk),
    .reset_n           (reset_n),
    .req               (dtlb_req),
    .ready             (dtlb_ready),
    .virtual_addr      (dmem_virtual_addr_q),
    .asid              (dmem_satp_q[30:22]),
    .access_type       (dmem_access_type_q),
    .privilege         (dmem_effective_privilege_q),
    .sum               (dmem_sum_q),
    .mxr               (dmem_mxr_q),
    .resp_valid        (dtlb_resp_valid),
    .hit               (dtlb_hit),
    .physical_addr     (dtlb_physical_addr),
    .page_fault        (dtlb_page_fault),
    .fill_valid        (dtlb_fill_valid),
    .fill_virtual_addr (dmem_virtual_addr_q),
    .fill_asid         (dmem_satp_q[30:22]),
    .fill              (walker_fill),
    .flush             (sfence_vma_flush)
);

always_comb begin
  walk_selected_owner = WALK_OWNER_NONE;
  walk_selected_valid = 1'b0;

  if (walk_next_priority_q == WALK_OWNER_IMEM) begin
    if (imem_state_q == TRANSLATE_WALK_REQ) begin
      walk_selected_owner = WALK_OWNER_IMEM;
      walk_selected_valid = 1'b1;
    end else if (dmem_state_q == TRANSLATE_WALK_REQ) begin
      walk_selected_owner = WALK_OWNER_DMEM;
      walk_selected_valid = 1'b1;
    end
  end else begin
    if (dmem_state_q == TRANSLATE_WALK_REQ) begin
      walk_selected_owner = WALK_OWNER_DMEM;
      walk_selected_valid = 1'b1;
    end else if (imem_state_q == TRANSLATE_WALK_REQ) begin
      walk_selected_owner = WALK_OWNER_IMEM;
      walk_selected_valid = 1'b1;
    end
  end
end

always_comb begin
  walker_req = walk_selected_valid;
  walker_virtual_addr = 32'h0;
  walker_access_type = VM_ACCESS_INSTRUCTION;
  walker_privilege = PRIVILEGE_M;
  walker_root_ppn = 22'h0;
  walker_sum = 1'b0;
  walker_mxr = 1'b0;

  unique case (walk_selected_owner)
    WALK_OWNER_IMEM: begin
      walker_virtual_addr = imem_virtual_addr_q;
      walker_privilege = imem_privilege_q;
      walker_root_ppn = imem_satp_q[21:0];
      walker_sum = imem_sum_q;
      walker_mxr = imem_mxr_q;
    end
    WALK_OWNER_DMEM: begin
      walker_virtual_addr = dmem_virtual_addr_q;
      walker_access_type = dmem_access_type_q;
      walker_privilege = dmem_effective_privilege_q;
      walker_root_ppn = dmem_satp_q[21:0];
      walker_sum = dmem_sum_q;
      walker_mxr = dmem_mxr_q;
    end
    default: begin
    end
  endcase
end

sv32_page_table_walker u_page_table_walker (
    .clk             (clk),
    .reset_n         (reset_n),
    .req             (walker_req),
    .ready           (walker_ready),
    .virtual_addr    (walker_virtual_addr),
    .access_type     (walker_access_type),
    .privilege       (walker_privilege),
    .root_ppn        (walker_root_ppn),
    .sum             (walker_sum),
    .mxr             (walker_mxr),
    .resp_valid      (walker_resp_valid),
    .page_fault      (walker_page_fault),
    .fill            (walker_fill),
    .mem_req         (mem_req),
    .mem_ready       (mem_ready),
    .mem_wr_en       (mem_wr_en),
    .mem_size        (mem_size),
    .mem_addr        (mem_addr),
    .mem_wr_data     (mem_wr_data),
    .mem_zero_extend (mem_zero_extend),
    .mem_lock        (mem_lock),
    .mem_resp_valid  (mem_resp_valid),
    .mem_rd_data     (mem_rd_data)
);

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    walk_owner_q <= WALK_OWNER_NONE;
    walk_next_priority_q <= WALK_OWNER_IMEM;
  end else if (walker_req && walker_ready) begin
    walk_owner_q <= walk_selected_owner;
    walk_next_priority_q <=
        (walk_selected_owner == WALK_OWNER_IMEM) ?
        WALK_OWNER_DMEM : WALK_OWNER_IMEM;
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    imem_state_q <= TRANSLATE_IDLE;
    imem_virtual_addr_q <= 32'h0;
    imem_privilege_q <= PRIVILEGE_M;
    imem_sum_q <= 1'b0;
    imem_mxr_q <= 1'b0;
    imem_satp_q <= 32'h0;
    imem_physical_addr_q <= 32'h0;
    imem_page_fault_q <= 1'b0;
  end else begin
    unique case (imem_state_q)
      TRANSLATE_IDLE: begin
        if (imem_req) begin
          imem_virtual_addr_q <= imem_virtual_addr;
          imem_privilege_q <= imem_privilege;
          imem_sum_q <= imem_sum;
          imem_mxr_q <= imem_mxr;
          imem_satp_q <= imem_satp;
          imem_page_fault_q <= 1'b0;
          imem_state_q <= TRANSLATE_TLB_REQ;
        end
      end
      TRANSLATE_TLB_REQ: begin
        if (!imem_translation_enabled) begin
          imem_physical_addr_q <= imem_virtual_addr_q;
          imem_state_q <= TRANSLATE_RESP;
        end else if (itlb_ready) begin
          imem_state_q <= TRANSLATE_TLB_WAIT;
        end
      end
      TRANSLATE_TLB_WAIT: begin
        if (itlb_resp_valid) begin
          if (itlb_hit) begin
            imem_physical_addr_q <= itlb_physical_addr;
            imem_page_fault_q <= itlb_page_fault;
            imem_state_q <= TRANSLATE_RESP;
          end else begin
            imem_state_q <= TRANSLATE_WALK_REQ;
          end
        end
      end
      TRANSLATE_WALK_REQ: begin
        if (walker_req && walker_ready &&
            (walk_selected_owner == WALK_OWNER_IMEM)) begin
          imem_state_q <= TRANSLATE_WALK_WAIT;
        end
      end
      TRANSLATE_WALK_WAIT: begin
        if (walker_resp_valid && (walk_owner_q == WALK_OWNER_IMEM)) begin
          imem_physical_addr_q <= walker_fill.physical_addr;
          imem_page_fault_q <= walker_page_fault;
          imem_state_q <= TRANSLATE_RESP;
        end
      end
      TRANSLATE_RESP: imem_state_q <= TRANSLATE_IDLE;
      default: imem_state_q <= TRANSLATE_IDLE;
    endcase
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    dmem_state_q <= TRANSLATE_IDLE;
    dmem_virtual_addr_q <= 32'h0;
    dmem_access_type_q <= VM_ACCESS_LOAD;
    dmem_effective_privilege_q <= PRIVILEGE_M;
    dmem_sum_q <= 1'b0;
    dmem_mxr_q <= 1'b0;
    dmem_satp_q <= 32'h0;
    dmem_physical_addr_q <= 32'h0;
    dmem_page_fault_q <= 1'b0;
  end else begin
    unique case (dmem_state_q)
      TRANSLATE_IDLE: begin
        if (dmem_req) begin
          dmem_virtual_addr_q <= dmem_virtual_addr;
          dmem_access_type_q <= dmem_access_type;
          dmem_effective_privilege_q <= dmem_effective_privilege;
          dmem_sum_q <= dmem_sum;
          dmem_mxr_q <= dmem_mxr;
          dmem_satp_q <= dmem_satp;
          dmem_page_fault_q <= 1'b0;
          dmem_state_q <= TRANSLATE_TLB_REQ;
        end
      end
      TRANSLATE_TLB_REQ: begin
        if (!dmem_translation_enabled) begin
          dmem_physical_addr_q <= dmem_virtual_addr_q;
          dmem_state_q <= TRANSLATE_RESP;
        end else if (dtlb_ready) begin
          dmem_state_q <= TRANSLATE_TLB_WAIT;
        end
      end
      TRANSLATE_TLB_WAIT: begin
        if (dtlb_resp_valid) begin
          if (dtlb_hit) begin
            dmem_physical_addr_q <= dtlb_physical_addr;
            dmem_page_fault_q <= dtlb_page_fault;
            dmem_state_q <= TRANSLATE_RESP;
          end else begin
            dmem_state_q <= TRANSLATE_WALK_REQ;
          end
        end
      end
      TRANSLATE_WALK_REQ: begin
        if (walker_req && walker_ready &&
            (walk_selected_owner == WALK_OWNER_DMEM)) begin
          dmem_state_q <= TRANSLATE_WALK_WAIT;
        end
      end
      TRANSLATE_WALK_WAIT: begin
        if (walker_resp_valid && (walk_owner_q == WALK_OWNER_DMEM)) begin
          dmem_physical_addr_q <= walker_fill.physical_addr;
          dmem_page_fault_q <= walker_page_fault;
          dmem_state_q <= TRANSLATE_RESP;
        end
      end
      TRANSLATE_RESP: dmem_state_q <= TRANSLATE_IDLE;
      default: dmem_state_q <= TRANSLATE_IDLE;
    endcase
  end
end

endmodule
