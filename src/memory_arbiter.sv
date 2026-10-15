import risc_pkg::*;

module memory_arbiter (
  input logic clk,
  input logic reset_n,

  input logic normal_req,
  output logic normal_ready,
  input logic normal_wr_en,
  input mem_size_t normal_size,
  input logic [31:0] normal_addr,
  input logic [31:0] normal_wr_data,
  input logic normal_zero_extend,
  input logic normal_lock,
  output logic normal_resp_valid,
  output logic [31:0] normal_rd_data,

  input logic atomic_req,
  output logic atomic_ready,
  input logic atomic_wr_en,
  input mem_size_t atomic_size,
  input logic [31:0] atomic_addr,
  input logic [31:0] atomic_wr_data,
  input logic atomic_zero_extend,
  input logic atomic_lock,
  output logic atomic_resp_valid,
  output logic [31:0] atomic_rd_data,

  input logic ptw_req,
  output logic ptw_ready,
  input logic ptw_wr_en,
  input mem_size_t ptw_size,
  input logic [31:0] ptw_addr,
  input logic [31:0] ptw_wr_data,
  input logic ptw_zero_extend,
  input logic ptw_lock,
  output logic ptw_resp_valid,
  output logic [31:0] ptw_rd_data,

  output logic mem_req,
  input logic mem_ready,
  output logic mem_wr_en,
  output mem_size_t mem_size,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wr_data,
  output logic mem_zero_extend,
  input logic mem_resp_valid,
  input logic [31:0] mem_rd_data,

  output logic write_valid,
  output logic [31:0] write_addr
);

typedef enum logic [1:0] {
  OWNER_NORMAL,
  OWNER_ATOMIC,
  OWNER_PTW
} owner_t;

typedef enum logic [1:0] {
  ARB_IDLE,
  ARB_ISSUE,
  ARB_WAIT
} arb_state_t;

arb_state_t state_q;
owner_t owner_q;
owner_t next_priority_q;
owner_t lock_owner_q;
owner_t selected_owner;

logic lock_active_q;
logic lock_enforced;
logic selected_valid;
logic selected_lock;
logic mem_fire;
logic response_expected;

function automatic logic owner_req(input owner_t owner);
  unique case (owner)
    OWNER_NORMAL: owner_req = normal_req;
    OWNER_ATOMIC: owner_req = atomic_req;
    OWNER_PTW: owner_req = ptw_req;
    default: owner_req = 1'b0;
  endcase
endfunction

function automatic logic owner_lock(input owner_t owner);
  unique case (owner)
    OWNER_NORMAL: owner_lock = normal_lock;
    OWNER_ATOMIC: owner_lock = atomic_lock;
    OWNER_PTW: owner_lock = ptw_lock;
    default: owner_lock = 1'b0;
  endcase
endfunction

function automatic owner_t next_owner(input owner_t owner);
  unique case (owner)
    OWNER_NORMAL: next_owner = OWNER_ATOMIC;
    OWNER_ATOMIC: next_owner = OWNER_PTW;
    default: next_owner = OWNER_NORMAL;
  endcase
endfunction

assign lock_enforced = lock_active_q && owner_lock(lock_owner_q);
assign selected_lock = owner_lock(selected_owner);
assign mem_fire = mem_req && mem_ready;
assign response_expected = (state_q == ARB_WAIT);

always_comb begin
  selected_owner = OWNER_NORMAL;
  selected_valid = 1'b0;

  if (lock_enforced) begin
    selected_owner = lock_owner_q;
    selected_valid = owner_req(lock_owner_q);
  end else begin
    unique case (next_priority_q)
      OWNER_NORMAL: begin
        if (normal_req) begin
          selected_owner = OWNER_NORMAL;
          selected_valid = 1'b1;
        end else if (atomic_req) begin
          selected_owner = OWNER_ATOMIC;
          selected_valid = 1'b1;
        end else if (ptw_req) begin
          selected_owner = OWNER_PTW;
          selected_valid = 1'b1;
        end
      end
      OWNER_ATOMIC: begin
        if (atomic_req) begin
          selected_owner = OWNER_ATOMIC;
          selected_valid = 1'b1;
        end else if (ptw_req) begin
          selected_owner = OWNER_PTW;
          selected_valid = 1'b1;
        end else if (normal_req) begin
          selected_owner = OWNER_NORMAL;
          selected_valid = 1'b1;
        end
      end
      default: begin
        if (ptw_req) begin
          selected_owner = OWNER_PTW;
          selected_valid = 1'b1;
        end else if (normal_req) begin
          selected_owner = OWNER_NORMAL;
          selected_valid = 1'b1;
        end else if (atomic_req) begin
          selected_owner = OWNER_ATOMIC;
          selected_valid = 1'b1;
        end
      end
    endcase
  end
end

always_comb begin
  mem_req = 1'b0;
  mem_wr_en = 1'b0;
  mem_size = WORD;
  mem_addr = 32'h0;
  mem_wr_data = 32'h0;
  mem_zero_extend = 1'b0;
  normal_ready = 1'b0;
  atomic_ready = 1'b0;
  ptw_ready = 1'b0;

  if (state_q == ARB_IDLE) begin
    mem_req = selected_valid;
    unique case (selected_owner)
      OWNER_NORMAL: begin
        mem_wr_en = normal_wr_en;
        mem_size = normal_size;
        mem_addr = normal_addr;
        mem_wr_data = normal_wr_data;
        mem_zero_extend = normal_zero_extend;
        normal_ready = selected_valid && mem_ready;
      end
      OWNER_ATOMIC: begin
        mem_wr_en = atomic_wr_en;
        mem_size = atomic_size;
        mem_addr = atomic_addr;
        mem_wr_data = atomic_wr_data;
        mem_zero_extend = atomic_zero_extend;
        atomic_ready = selected_valid && mem_ready;
      end
      default: begin
        mem_wr_en = ptw_wr_en;
        mem_size = ptw_size;
        mem_addr = ptw_addr;
        mem_wr_data = ptw_wr_data;
        mem_zero_extend = ptw_zero_extend;
        ptw_ready = selected_valid && mem_ready;
      end
    endcase
  end else if (state_q == ARB_ISSUE) begin
    unique case (owner_q)
      OWNER_NORMAL: begin
        mem_req = normal_req;
        mem_wr_en = normal_wr_en;
        mem_size = normal_size;
        mem_addr = normal_addr;
        mem_wr_data = normal_wr_data;
        mem_zero_extend = normal_zero_extend;
        normal_ready = mem_ready;
      end
      OWNER_ATOMIC: begin
        mem_req = atomic_req;
        mem_wr_en = atomic_wr_en;
        mem_size = atomic_size;
        mem_addr = atomic_addr;
        mem_wr_data = atomic_wr_data;
        mem_zero_extend = atomic_zero_extend;
        atomic_ready = mem_ready;
      end
      default: begin
        mem_req = ptw_req;
        mem_wr_en = ptw_wr_en;
        mem_size = ptw_size;
        mem_addr = ptw_addr;
        mem_wr_data = ptw_wr_data;
        mem_zero_extend = ptw_zero_extend;
        ptw_ready = mem_ready;
      end
    endcase
  end
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    normal_resp_valid <= 1'b0;
    atomic_resp_valid <= 1'b0;
    ptw_resp_valid <= 1'b0;
    normal_rd_data <= 32'h0;
    atomic_rd_data <= 32'h0;
    ptw_rd_data <= 32'h0;
  end else begin
    normal_resp_valid <= 1'b0;
    atomic_resp_valid <= 1'b0;
    ptw_resp_valid <= 1'b0;

    if (mem_resp_valid && response_expected) begin
      unique case (owner_q)
        OWNER_NORMAL: begin
          normal_resp_valid <= 1'b1;
          normal_rd_data <= mem_rd_data;
        end
        OWNER_ATOMIC: begin
          atomic_resp_valid <= 1'b1;
          atomic_rd_data <= mem_rd_data;
        end
        default: begin
          ptw_resp_valid <= 1'b1;
          ptw_rd_data <= mem_rd_data;
        end
      endcase
    end
  end
end

assign write_valid = mem_fire && mem_wr_en;
assign write_addr = mem_addr;

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    state_q <= ARB_IDLE;
    owner_q <= OWNER_NORMAL;
    next_priority_q <= OWNER_NORMAL;
    lock_active_q <= 1'b0;
    lock_owner_q <= OWNER_NORMAL;
  end else begin
    if (lock_active_q && !owner_lock(lock_owner_q)) begin
      lock_active_q <= 1'b0;
    end

    unique case (state_q)
      ARB_IDLE: begin
        if (selected_valid) begin
          owner_q <= selected_owner;
          if (selected_lock) begin
            lock_active_q <= 1'b1;
            lock_owner_q <= selected_owner;
          end

          if (mem_fire) begin
            next_priority_q <= next_owner(selected_owner);
            state_q <= ARB_WAIT;
          end else begin
            state_q <= ARB_ISSUE;
          end
        end
      end
      ARB_ISSUE: begin
        if (mem_fire) begin
          next_priority_q <= next_owner(owner_q);
          state_q <= ARB_WAIT;
        end
      end
      ARB_WAIT: begin
        if (mem_resp_valid) begin
          state_q <= ARB_IDLE;
        end
      end
      default: state_q <= ARB_IDLE;
    endcase
  end
end

endmodule
