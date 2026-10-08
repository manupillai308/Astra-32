import risc_pkg::*;

module mul_div (
  input  logic        clk,
  input  logic        reset_n,

  input  logic        req,
  output logic        ready,
  input  mul_div_op_t op,
  input  logic [31:0] lhs,
  input  logic [31:0] rhs,

  output logic        resp_valid,
  output logic [31:0] result
);

typedef enum logic [1:0] {
  MULDIV_IDLE,
  MULDIV_MULTIPLY,
  MULDIV_DIVIDE
} mul_div_state_t;

mul_div_state_t state_q;
logic [5:0] iteration_q;

logic [63:0] mul_accumulator_q;
logic [63:0] mul_multiplicand_q;
logic [31:0] mul_multiplier_q;
logic        mul_result_negative_q;
logic        mul_return_high_q;

logic [32:0] div_remainder_q;
logic [31:0] div_quotient_q;
logic [31:0] div_divisor_q;
logic        div_quotient_negative_q;
logic        div_remainder_negative_q;
logic        div_return_remainder_q;

logic        lhs_is_signed;
logic        rhs_is_signed;
logic [31:0] lhs_magnitude;
logic [31:0] rhs_magnitude;
logic [63:0] mul_accumulator_next;
logic [63:0] mul_product;
logic [32:0] div_remainder_next;
logic [31:0] div_quotient_next;
logic [31:0] div_signed_quotient;
logic [31:0] div_signed_remainder;

assign ready = (state_q == MULDIV_IDLE);

always_comb begin
  lhs_is_signed = (op == MULDIV_MULH) || (op == MULDIV_MULHSU) ||
                  (op == MULDIV_DIV) || (op == MULDIV_REM);
  rhs_is_signed = (op == MULDIV_MULH) ||
                  (op == MULDIV_DIV) || (op == MULDIV_REM);
  lhs_magnitude = (lhs_is_signed && lhs[31]) ? (~lhs + 1'b1) : lhs;
  rhs_magnitude = (rhs_is_signed && rhs[31]) ? (~rhs + 1'b1) : rhs;
end

assign mul_accumulator_next = mul_accumulator_q +
                              (mul_multiplier_q[0] ? mul_multiplicand_q : 64'h0);
assign mul_product = mul_result_negative_q ? (~mul_accumulator_next + 1'b1) :
                                             mul_accumulator_next;

always_comb begin
  div_remainder_next = {div_remainder_q[31:0], div_quotient_q[31]};
  div_quotient_next = {div_quotient_q[30:0], 1'b0};

  if (div_remainder_next >= {1'b0, div_divisor_q}) begin
    div_remainder_next = div_remainder_next - {1'b0, div_divisor_q};
    div_quotient_next[0] = 1'b1;
  end

  div_signed_quotient = div_quotient_negative_q ? (~div_quotient_next + 1'b1) :
                                                  div_quotient_next;
  div_signed_remainder = div_remainder_negative_q ?
                         (~div_remainder_next[31:0] + 1'b1) :
                         div_remainder_next[31:0];
end

always_ff @(posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    state_q <= MULDIV_IDLE;
    iteration_q <= 6'h0;
    mul_accumulator_q <= 64'h0;
    mul_multiplicand_q <= 64'h0;
    mul_multiplier_q <= 32'h0;
    mul_result_negative_q <= 1'b0;
    mul_return_high_q <= 1'b0;
    div_remainder_q <= 33'h0;
    div_quotient_q <= 32'h0;
    div_divisor_q <= 32'h0;
    div_quotient_negative_q <= 1'b0;
    div_remainder_negative_q <= 1'b0;
    div_return_remainder_q <= 1'b0;
    resp_valid <= 1'b0;
    result <= 32'h0;
  end else begin
    resp_valid <= 1'b0;

    unique case (state_q)
      MULDIV_IDLE: begin
        if (req) begin
          iteration_q <= 6'h0;

          if (!op[2]) begin
            mul_accumulator_q <= 64'h0;
            mul_multiplicand_q <= {32'h0, lhs_magnitude};
            mul_multiplier_q <= rhs_magnitude;
            mul_result_negative_q <= (lhs_is_signed && lhs[31]) ^
                                     (rhs_is_signed && rhs[31]);
            mul_return_high_q <= (op != MULDIV_MUL);
            state_q <= MULDIV_MULTIPLY;
          end else if (rhs == 32'h0) begin
            result <= ((op == MULDIV_REM) || (op == MULDIV_REMU)) ?
                      lhs : 32'hffff_ffff;
            resp_valid <= 1'b1;
          end else if (((op == MULDIV_DIV) || (op == MULDIV_REM)) &&
                       (lhs == 32'h8000_0000) && (rhs == 32'hffff_ffff)) begin
            result <= (op == MULDIV_DIV) ? 32'h8000_0000 : 32'h0;
            resp_valid <= 1'b1;
          end else begin
            div_remainder_q <= 33'h0;
            div_quotient_q <= lhs_magnitude;
            div_divisor_q <= rhs_magnitude;
            div_quotient_negative_q <=
                ((op == MULDIV_DIV) || (op == MULDIV_REM)) && (lhs[31] ^ rhs[31]);
            div_remainder_negative_q <=
                ((op == MULDIV_DIV) || (op == MULDIV_REM)) && lhs[31];
            div_return_remainder_q <= (op == MULDIV_REM) || (op == MULDIV_REMU);
            state_q <= MULDIV_DIVIDE;
          end
        end
      end

      MULDIV_MULTIPLY: begin
        if (iteration_q == 6'd31) begin
          result <= mul_return_high_q ? mul_product[63:32] : mul_product[31:0];
          resp_valid <= 1'b1;
          state_q <= MULDIV_IDLE;
        end else begin
          mul_accumulator_q <= mul_accumulator_next;
          mul_multiplicand_q <= mul_multiplicand_q << 1;
          mul_multiplier_q <= mul_multiplier_q >> 1;
          iteration_q <= iteration_q + 1'b1;
        end
      end

      MULDIV_DIVIDE: begin
        if (iteration_q == 6'd31) begin
          result <= div_return_remainder_q ? div_signed_remainder :
                                             div_signed_quotient;
          resp_valid <= 1'b1;
          state_q <= MULDIV_IDLE;
        end else begin
          div_remainder_q <= div_remainder_next;
          div_quotient_q <= div_quotient_next;
          iteration_q <= iteration_q + 1'b1;
        end
      end

      default: state_q <= MULDIV_IDLE;
    endcase
  end
end

endmodule
