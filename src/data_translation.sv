import risc_pkg::*;

module data_translation (
  input  logic             clk,
  input  logic             reset_n,

  input  logic             req,
  output logic             ready,
  input  logic [31:0]      virtual_addr,
  input  vm_access_t       access_type,
  input  privilege_mode_t  current_privilege,
  input  logic             mstatus_mprv,
  input  privilege_mode_t  mstatus_mpp,
  input  logic             mstatus_sum,
  input  logic             mstatus_mxr,
  input  logic [31:0]      satp,

  output logic             resp_valid,
  output logic [31:0]      physical_addr,
  output logic             page_fault,

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

typedef enum logic [1:0] {
  TRANSLATION_IDLE,
  TRANSLATION_WALK_REQ,
  TRANSLATION_WALK_WAIT,
  TRANSLATION_RESP
} translation_state_t;

translation_state_t state_q;
logic [31:0] virtual_addr_q;
vm_access_t access_type_q;
privilege_mode_t effective_privilege_q;
logic [21:0] root_ppn_q;
logic sum_q;
logic mxr_q;
logic [31:0] physical_addr_q;
logic page_fault_q;

privilege_mode_t effective_privilege;
logic translation_enabled;
logic walker_req;
logic walker_ready;
logic walker_resp_valid;
logic [31:0] walker_physical_addr;
logic walker_page_fault;

always_comb begin
  effective_privilege = current_privilege;
  if ((current_privilege == PRIVILEGE_M) && mstatus_mprv) begin
    effective_privilege = mstatus_mpp;
  end
end

assign translation_enabled = satp[31] &&
                             (effective_privilege != PRIVILEGE_M);
assign ready = (state_q == TRANSLATION_IDLE);
assign resp_valid = (state_q == TRANSLATION_RESP);
assign physical_addr = physical_addr_q;
assign page_fault = page_fault_q;
assign walker_req = (state_q == TRANSLATION_WALK_REQ);

sv32_page_table_walker u_page_table_walker (
    .clk             (clk),
    .reset_n         (reset_n),
    .req             (walker_req),
    .ready           (walker_ready),
    .virtual_addr    (virtual_addr_q),
    .access_type     (access_type_q),
    .privilege       (effective_privilege_q),
    .root_ppn        (root_ppn_q),
    .sum             (sum_q),
    .mxr             (mxr_q),
    .resp_valid      (walker_resp_valid),
    .physical_addr   (walker_physical_addr),
    .page_fault      (walker_page_fault),
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
    state_q <= TRANSLATION_IDLE;
    virtual_addr_q <= 32'h0;
    access_type_q <= VM_ACCESS_LOAD;
    effective_privilege_q <= PRIVILEGE_M;
    root_ppn_q <= 22'h0;
    sum_q <= 1'b0;
    mxr_q <= 1'b0;
    physical_addr_q <= 32'h0;
    page_fault_q <= 1'b0;
  end else begin
    unique case (state_q)
      TRANSLATION_IDLE: begin
        if (req) begin
          virtual_addr_q <= virtual_addr;
          access_type_q <= access_type;
          effective_privilege_q <= effective_privilege;
          root_ppn_q <= satp[21:0];
          sum_q <= mstatus_sum;
          mxr_q <= mstatus_mxr;
          physical_addr_q <= virtual_addr;
          page_fault_q <= 1'b0;
          state_q <= translation_enabled ? TRANSLATION_WALK_REQ :
                                           TRANSLATION_RESP;
        end
      end

      TRANSLATION_WALK_REQ: begin
        if (walker_ready) state_q <= TRANSLATION_WALK_WAIT;
      end

      TRANSLATION_WALK_WAIT: begin
        if (walker_resp_valid) begin
          physical_addr_q <= walker_physical_addr;
          page_fault_q <= walker_page_fault;
          state_q <= TRANSLATION_RESP;
        end
      end

      TRANSLATION_RESP: state_q <= TRANSLATION_IDLE;
      default: state_q <= TRANSLATION_IDLE;
    endcase
  end
end

endmodule
