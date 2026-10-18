import risc_pkg::*;

module sv32_tlb #(
  parameter int ENTRY_COUNT = 16
)(
  input  logic            clk,
  input  logic            reset_n,

  input  logic            req,
  output logic            ready,
  input  logic [31:0]     virtual_addr,
  input  logic [8:0]      asid,
  input  vm_access_t      access_type,
  input  privilege_mode_t privilege,
  input  logic            sum,
  input  logic            mxr,

  output logic            resp_valid,
  output logic            hit,
  output logic [31:0]     physical_addr,
  output logic            page_fault,

  input  logic            fill_valid,
  input  logic [31:0]     fill_virtual_addr,
  input  logic [8:0]      fill_asid,
  input  tlb_fill_t       fill,
  input  logic            flush
);

localparam int INDEX_WIDTH = (ENTRY_COUNT <= 1) ? 1 : $clog2(ENTRY_COUNT);

typedef struct packed {
  logic        valid;
  logic [19:0] vpn;
  logic [19:0] ppn;
  logic [8:0]  asid;
  logic        superpage;
  logic        read;
  logic        write;
  logic        execute;
  logic        user;
  logic        accessed;
  logic        dirty;
} tlb_entry_t;

tlb_entry_t entries [0:ENTRY_COUNT-1];
logic [INDEX_WIDTH-1:0] replacement_q;

logic resp_valid_q;
logic hit_q;
logic [31:0] physical_addr_q;
logic page_fault_q;

logic lookup_found;
logic lookup_hit;
logic [31:0] lookup_physical_addr;
logic lookup_page_fault;
logic fill_found;
logic [INDEX_WIDTH-1:0] fill_index;

integer lookup_index;
integer fill_search_index;
integer reset_index;

function automatic logic permission_fault(
  input tlb_entry_t entry,
  input vm_access_t requested_access,
  input privilege_mode_t requested_privilege,
  input logic requested_sum,
  input logic requested_mxr
);
  logic fault;
  begin
    unique case (requested_access)
      VM_ACCESS_INSTRUCTION: fault = !entry.execute;
      VM_ACCESS_LOAD: fault = !(entry.read ||
                                (requested_mxr && entry.execute));
      VM_ACCESS_STORE: fault = !entry.write;
      default: fault = 1'b1;
    endcase

    if (requested_privilege == PRIVILEGE_U) begin
      fault |= !entry.user;
    end else if ((requested_privilege == PRIVILEGE_S) && entry.user) begin
      fault |= (requested_access == VM_ACCESS_INSTRUCTION) || !requested_sum;
    end

    permission_fault = fault;
  end
endfunction

assign ready = !resp_valid_q;
assign resp_valid = resp_valid_q;
assign hit = hit_q;
assign physical_addr = physical_addr_q;
assign page_fault = page_fault_q;

always_comb begin
  lookup_found = 1'b0;
  lookup_hit = 1'b0;
  lookup_physical_addr = 32'h0;
  lookup_page_fault = 1'b0;

  for (lookup_index = 0; lookup_index < ENTRY_COUNT;
       lookup_index = lookup_index + 1) begin
    if (!lookup_found && entries[lookup_index].valid &&
        (entries[lookup_index].asid == asid) &&
        (entries[lookup_index].superpage ?
         (entries[lookup_index].vpn[19:10] == virtual_addr[31:22]) :
         (entries[lookup_index].vpn == virtual_addr[31:12]))) begin
      lookup_found = 1'b1;

      // Permission changes such as SUM and MXR take effect without a refill.
      if (permission_fault(entries[lookup_index], access_type, privilege,
                           sum, mxr)) begin
        lookup_hit = 1'b1;
        lookup_page_fault = 1'b1;
      // Missing A/D state is a miss so the PTW can update the leaf PTE.
      end else if (entries[lookup_index].accessed &&
                   ((access_type != VM_ACCESS_STORE) ||
                    entries[lookup_index].dirty)) begin
        lookup_hit = 1'b1;
        lookup_physical_addr = entries[lookup_index].superpage ?
                               {entries[lookup_index].ppn[19:10],
                                virtual_addr[21:0]} :
                               {entries[lookup_index].ppn,
                                virtual_addr[11:0]};
      end
    end
  end
end

always_comb begin
  fill_found = 1'b0;
  fill_index = replacement_q;

  for (fill_search_index = 0; fill_search_index < ENTRY_COUNT;
       fill_search_index = fill_search_index + 1) begin
    if (!fill_found && entries[fill_search_index].valid &&
        (entries[fill_search_index].asid == fill_asid) &&
        (entries[fill_search_index].superpage == fill.superpage) &&
        (fill.superpage ?
         (entries[fill_search_index].vpn[19:10] ==
          fill_virtual_addr[31:22]) :
         (entries[fill_search_index].vpn == fill_virtual_addr[31:12]))) begin
      fill_found = 1'b1;
      fill_index = fill_search_index[INDEX_WIDTH-1:0];
    end
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    replacement_q <= '0;
    resp_valid_q <= 1'b0;
    hit_q <= 1'b0;
    physical_addr_q <= 32'h0;
    page_fault_q <= 1'b0;
    for (reset_index = 0; reset_index < ENTRY_COUNT;
         reset_index = reset_index + 1) begin
      entries[reset_index] <= '0;
    end
  end else begin
    resp_valid_q <= 1'b0;

    // Register the lookup result to keep the associative search off CPU paths.
    if (req && ready) begin
      resp_valid_q <= 1'b1;
      hit_q <= lookup_hit;
      physical_addr_q <= lookup_physical_addr;
      page_fault_q <= lookup_page_fault;
    end

    // This implementation legally treats every SFENCE.VMA as a global flush.
    if (flush) begin
      for (reset_index = 0; reset_index < ENTRY_COUNT;
           reset_index = reset_index + 1) begin
        entries[reset_index].valid <= 1'b0;
      end
    end else if (fill_valid) begin
      entries[fill_index].valid <= 1'b1;
      entries[fill_index].vpn <= fill_virtual_addr[31:12];
      entries[fill_index].ppn <= fill.ppn;
      entries[fill_index].asid <= fill_asid;
      entries[fill_index].superpage <= fill.superpage;
      entries[fill_index].read <= fill.read;
      entries[fill_index].write <= fill.write;
      entries[fill_index].execute <= fill.execute;
      entries[fill_index].user <= fill.user;
      entries[fill_index].accessed <= fill.accessed;
      entries[fill_index].dirty <= fill.dirty;

      if (!fill_found) begin
        replacement_q <= (replacement_q == ENTRY_COUNT - 1) ? '0 :
                         replacement_q + 1'b1;
      end
    end
  end
end

endmodule
