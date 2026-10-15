import risc_pkg::*;

module sv32_page_table_walker (
  input logic clk,
  input logic reset_n,

  input logic req,
  output logic ready,
  input logic [31:0] virtual_addr,
  input vm_access_t access_type,
  input privilege_mode_t privilege,
  input logic [21:0] root_ppn,
  input logic sum,
  input logic mxr,

  output logic resp_valid,
  output logic [31:0] physical_addr,
  output logic page_fault,

  output logic mem_req,
  input logic mem_ready,
  output logic mem_wr_en,
  output mem_size_t mem_size,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wr_data,
  output logic mem_zero_extend,
  output logic mem_lock,
  input logic mem_resp_valid,
  input logic [31:0] mem_rd_data
);

typedef enum logic [2:0] {
  PTW_IDLE,
  PTW_LEVEL_1_REQ,
  PTW_LEVEL_1_WAIT,
  PTW_LEVEL_0_REQ,
  PTW_LEVEL_0_WAIT,
  PTW_AD_WRITE_REQ,
  PTW_AD_WRITE_WAIT,
  PTW_RESP
} ptw_state_t;

ptw_state_t state_q;
logic [31:0] virtual_addr_q;
vm_access_t access_type_q;
privilege_mode_t privilege_q;
logic sum_q;
logic mxr_q;
logic [31:0] pte_addr_q;
logic [31:0] updated_pte_q;
logic [31:0] physical_addr_q;
logic page_fault_q;

logic current_level_1;
logic pte_read;
logic pte_write;
logic pte_execute;
logic pte_user;
logic pte_leaf;
logic pte_encoding_invalid;
logic pte_nonleaf_reserved;
logic pte_permission_fault;
logic pte_physical_width_fault;
logic pte_superpage_misaligned;
logic pte_ad_update_required;
logic [31:0] translated_addr;

assign ready = (state_q == PTW_IDLE);
assign resp_valid = (state_q == PTW_RESP);
assign physical_addr = physical_addr_q;
assign page_fault = page_fault_q;

assign mem_req = (state_q == PTW_LEVEL_1_REQ) ||
                 (state_q == PTW_LEVEL_0_REQ) ||
                 (state_q == PTW_AD_WRITE_REQ);
assign mem_wr_en = (state_q == PTW_AD_WRITE_REQ);
assign mem_size = WORD;
assign mem_addr = pte_addr_q;
assign mem_wr_data = updated_pte_q;
assign mem_zero_extend = 1'b0;
assign mem_lock = (state_q != PTW_IDLE);

assign current_level_1 = (state_q == PTW_LEVEL_1_WAIT);
assign pte_read = mem_rd_data[1];
assign pte_write = mem_rd_data[2];
assign pte_execute = mem_rd_data[3];
assign pte_user = mem_rd_data[4];
assign pte_leaf = pte_read || pte_execute;
assign pte_encoding_invalid = !mem_rd_data[0] || (!pte_read && pte_write);
assign pte_nonleaf_reserved = !pte_leaf &&
                              (mem_rd_data[7] || mem_rd_data[6] || pte_user);
assign pte_physical_width_fault = |mem_rd_data[31:30];
assign pte_superpage_misaligned = current_level_1 &&
                                   (mem_rd_data[19:10] != 10'h0);
assign pte_ad_update_required = !mem_rd_data[6] ||
                                ((access_type_q == VM_ACCESS_STORE) && !mem_rd_data[7]);

always_comb begin
  pte_permission_fault = 1'b0;

  unique case (access_type_q)
    VM_ACCESS_INSTRUCTION: pte_permission_fault = !pte_execute;
    VM_ACCESS_LOAD: pte_permission_fault = !(pte_read || (mxr_q && pte_execute));
    VM_ACCESS_STORE: pte_permission_fault = !pte_write;
    default: pte_permission_fault = 1'b1;
  endcase

  if (privilege_q == PRIVILEGE_U) begin
    pte_permission_fault |= !pte_user;
  end else if ((privilege_q == PRIVILEGE_S) && pte_user) begin
    pte_permission_fault |= (access_type_q == VM_ACCESS_INSTRUCTION) || !sum_q;
  end
end

always_comb begin
  if (current_level_1) begin
    translated_addr = {mem_rd_data[29:20], virtual_addr_q[21:0]};
  end else begin
    translated_addr = {mem_rd_data[29:10], virtual_addr_q[11:0]};
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    state_q <= PTW_IDLE;
    virtual_addr_q <= 32'h0;
    access_type_q <= VM_ACCESS_INSTRUCTION;
    privilege_q <= PRIVILEGE_M;
    sum_q <= 1'b0;
    mxr_q <= 1'b0;
    pte_addr_q <= 32'h0;
    updated_pte_q <= 32'h0;
    physical_addr_q <= 32'h0;
    page_fault_q <= 1'b0;
  end else begin
    unique case (state_q)
      PTW_IDLE: begin
        if (req) begin
          virtual_addr_q <= virtual_addr;
          access_type_q <= access_type;
          privilege_q <= privilege;
          sum_q <= sum;
          mxr_q <= mxr;
          physical_addr_q <= 32'h0;
          page_fault_q <= 1'b0;

          if (root_ppn[21:20] != 2'b00) begin
            page_fault_q <= 1'b1;
            state_q <= PTW_RESP;
          end else begin
            pte_addr_q <= {root_ppn[19:0], 12'h000} +
                          {20'h0, virtual_addr[31:22], 2'b00};
            state_q <= PTW_LEVEL_1_REQ;
          end
        end
      end

      PTW_LEVEL_1_REQ: begin
        if (mem_ready) state_q <= PTW_LEVEL_1_WAIT;
      end

      PTW_LEVEL_0_REQ: begin
        if (mem_ready) state_q <= PTW_LEVEL_0_WAIT;
      end

      PTW_LEVEL_1_WAIT,
      PTW_LEVEL_0_WAIT: begin
        if (mem_resp_valid) begin
          if (pte_encoding_invalid || pte_nonleaf_reserved ||
              pte_physical_width_fault) begin
            page_fault_q <= 1'b1;
            state_q <= PTW_RESP;
          end else if (!pte_leaf) begin
            if (!current_level_1) begin
              page_fault_q <= 1'b1;
              state_q <= PTW_RESP;
            end else begin
              pte_addr_q <= {mem_rd_data[29:10], 12'h000} +
                            {20'h0, virtual_addr_q[21:12], 2'b00};
              state_q <= PTW_LEVEL_0_REQ;
            end
          end else if (pte_superpage_misaligned || pte_permission_fault) begin
            page_fault_q <= 1'b1;
            state_q <= PTW_RESP;
          end else begin
            physical_addr_q <= translated_addr;
            if (pte_ad_update_required) begin
              updated_pte_q <= mem_rd_data | 32'h0000_0040 |
                               ((access_type_q == VM_ACCESS_STORE) ?
                                32'h0000_0080 : 32'h0);
              state_q <= PTW_AD_WRITE_REQ;
            end else begin
              state_q <= PTW_RESP;
            end
          end
        end
      end

      PTW_AD_WRITE_REQ: begin
        if (mem_ready) state_q <= PTW_AD_WRITE_WAIT;
      end

      PTW_AD_WRITE_WAIT: begin
        if (mem_resp_valid) state_q <= PTW_RESP;
      end

      PTW_RESP: state_q <= PTW_IDLE;
      default: state_q <= PTW_IDLE;
    endcase
  end
end

endmodule
