import risc_pkg::*;

module atomic_unit (
  input  logic        clk,
  input  logic        reset_n,

  input  logic        req,
  output logic        ready,
  input  atomic_op_t  op,
  input  logic [31:0] addr,
  input  logic [31:0] operand,

  output logic        resp_valid,
  output logic [31:0] result,

  output logic        mem_req,
  output logic        mem_wr_en,
  output logic [31:0] mem_addr,
  output logic [31:0] mem_wr_data,
  input  logic        mem_ready,
  input  logic        mem_resp_valid,
  input  logic [31:0] mem_rd_data,

  input  logic        clear_reservation,
  input  logic        local_write_valid,
  input  logic [31:0] local_write_addr,
  input  logic        external_write_valid,
  input  logic [31:0] external_write_addr,
  output logic        exclusive_active
);

typedef enum logic [2:0] {
  ATOMIC_IDLE,
  ATOMIC_READ_REQ,
  ATOMIC_READ_WAIT,
  ATOMIC_WRITE_REQ,
  ATOMIC_WRITE_WAIT
} atomic_state_t;

atomic_state_t state_q;
atomic_op_t    op_q;
logic [31:0]  addr_q;
logic [31:0]  operand_q;
logic [31:0]  old_value_q;
logic [31:0]  write_value_q;

logic        reservation_valid_q;
logic [29:0] reservation_addr_q;
logic        local_write_overlap;
logic        external_write_overlap;
logic        sc_reservation_match;
logic [31:0] amo_write_value;

assign ready = (state_q == ATOMIC_IDLE);
assign mem_req = (state_q == ATOMIC_READ_REQ) ||
                 (state_q == ATOMIC_WRITE_REQ);
assign mem_wr_en = (state_q == ATOMIC_WRITE_REQ);
assign mem_addr = addr_q;
assign mem_wr_data = write_value_q;

// writes from the local hart
assign local_write_overlap = local_write_valid && reservation_valid_q &&
                             (local_write_addr[31:2] == reservation_addr_q);
// writes from source external to hart
assign external_write_overlap = external_write_valid && reservation_valid_q &&
                                (external_write_addr[31:2] == reservation_addr_q);
assign sc_reservation_match = reservation_valid_q &&
                              (addr[31:2] == reservation_addr_q) &&
                              !clear_reservation &&
                              !local_write_overlap &&
                              !external_write_overlap;

assign exclusive_active = (state_q != ATOMIC_IDLE) && (op_q != ATOMIC_LR);

always_comb begin
  unique case (op_q)
    ATOMIC_SWAP: amo_write_value = operand_q;
    ATOMIC_ADD:  amo_write_value = mem_rd_data + operand_q;
    ATOMIC_XOR:  amo_write_value = mem_rd_data ^ operand_q;
    ATOMIC_AND:  amo_write_value = mem_rd_data & operand_q;
    ATOMIC_OR:   amo_write_value = mem_rd_data | operand_q;
    ATOMIC_MIN:  amo_write_value = ($signed(mem_rd_data) < $signed(operand_q)) ?
                                    mem_rd_data : operand_q;
    ATOMIC_MAX:  amo_write_value = ($signed(mem_rd_data) > $signed(operand_q)) ?
                                    mem_rd_data : operand_q;
    ATOMIC_MINU: amo_write_value = (mem_rd_data < operand_q) ? mem_rd_data : operand_q;
    ATOMIC_MAXU: amo_write_value = (mem_rd_data > operand_q) ? mem_rd_data : operand_q;
    default:     amo_write_value = operand_q;
  endcase
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    state_q <= ATOMIC_IDLE;
    op_q <= ATOMIC_LR;
    addr_q <= 32'h0;
    operand_q <= 32'h0;
    old_value_q <= 32'h0;
    write_value_q <= 32'h0;
    reservation_valid_q <= 1'b0;
    reservation_addr_q <= 30'h0;
    resp_valid <= 1'b0;
    result <= 32'h0;
  end else begin
    resp_valid <= 1'b0;

    if (clear_reservation || local_write_overlap || external_write_overlap) begin
      reservation_valid_q <= 1'b0;
    end

    unique case (state_q)
      ATOMIC_IDLE: begin
        if (req) begin
          op_q <= op;
          addr_q <= addr;
          operand_q <= operand;

          if (op == ATOMIC_SC) begin
            reservation_valid_q <= 1'b0;
            if (sc_reservation_match) begin
              write_value_q <= operand;
              state_q <= ATOMIC_WRITE_REQ;
            end else begin
              result <= 32'd1;
              resp_valid <= 1'b1;
            end
          end else begin
            state_q <= ATOMIC_READ_REQ;
          end
        end
      end

      ATOMIC_READ_REQ: begin
        if (mem_ready) begin
          state_q <= ATOMIC_READ_WAIT;
        end
      end

      ATOMIC_READ_WAIT: begin
        if (mem_resp_valid) begin
          if (op_q == ATOMIC_LR) begin
            reservation_valid_q <= !(clear_reservation || local_write_overlap ||
                                     external_write_overlap);
            reservation_addr_q <= addr_q[31:2];
            result <= mem_rd_data;
            resp_valid <= 1'b1;
            state_q <= ATOMIC_IDLE;
          end else begin
            old_value_q <= mem_rd_data;
            write_value_q <= amo_write_value;
            state_q <= ATOMIC_WRITE_REQ;
          end
        end
      end

      ATOMIC_WRITE_REQ: begin
        if (mem_ready) begin
          if (reservation_valid_q && (addr_q[31:2] == reservation_addr_q)) begin
            reservation_valid_q <= 1'b0;
          end
          state_q <= ATOMIC_WRITE_WAIT;
        end
      end

      ATOMIC_WRITE_WAIT: begin
        if (mem_resp_valid) begin
          result <= (op_q == ATOMIC_SC) ? 32'd0 : old_value_q;
          resp_valid <= 1'b1;
          state_q <= ATOMIC_IDLE;
        end
      end

      default: state_q <= ATOMIC_IDLE;
    endcase
  end
end

endmodule
