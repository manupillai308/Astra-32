// --------------------------------------------------------
// Data Memory - RTL (Refined, Parameterized)
// --------------------------------------------------------

import risc_pkg::*;

module data_memory #(
  parameter ADDR_WIDTH = 6,  // byte address bits: 2^6 = 64 bytes
  parameter int STALL_CYCLES = 2
)(
  input logic 				  clk,
  input logic                 reset_n,
  input  logic                dmem_req,                 
  input  logic                dmem_wr_en,               
  input mem_size_t		      dmem_data_size,           
  input  logic [31:0]         dmem_addr,                
  input  logic [31:0]         dmem_wr_data,             
  input  logic                dmem_zero_extend,         

  output logic [31:0]         dmem_rd_data,
  output logic                dmem_busy        
);

// --------------------------------------------------------
// RAM Declaration
// --------------------------------------------------------
localparam int WORD_ADDR_WIDTH = ADDR_WIDTH - 2;
localparam int STALL_COUNTER_WIDTH = (STALL_CYCLES <= 1) ? 1 : $clog2(STALL_CYCLES + 1);

(* ram_style = "block" *)
logic [31:0] mem [0:(2**WORD_ADDR_WIDTH)-1];
logic [WORD_ADDR_WIDTH-1:0] req_word_addr;
logic [1:0] req_byte_offset;
logic req_wr_en;
mem_size_t req_data_size;
logic [31:0] req_wr_data;
logic req_zero_extend;
logic [1:0] ram_byte_offset;
mem_size_t ram_data_size;
logic ram_zero_extend;
logic [31:0] ram_rd_data;

logic busy_q;
logic [STALL_COUNTER_WIDTH-1:0] stall_counter;

assign dmem_busy = busy_q || dmem_req;

// write logic - store

always_ff @ (posedge clk or negedge reset_n) begin
  if (!reset_n) begin
    busy_q <= 1'b0;
    stall_counter <= '0;
    req_word_addr <= '0;
    req_byte_offset <= '0;
    req_wr_en <= 1'b0;
    req_data_size <= WORD;
    req_wr_data <= 32'h0;
    req_zero_extend <= 1'b0;
    ram_rd_data <= 32'h0;
    ram_zero_extend <= 1'b0;
    ram_data_size <= WORD;
    ram_byte_offset <= '0;
  end else if (!busy_q && dmem_req) begin
    busy_q <= 1'b1;
    stall_counter <= STALL_CYCLES;
    req_word_addr <= dmem_addr[ADDR_WIDTH-1:2];
    req_byte_offset <= dmem_addr[1:0];
    req_wr_en <= dmem_wr_en;
    req_data_size <= dmem_data_size;
    req_wr_data <= dmem_wr_data;
    req_zero_extend <= dmem_zero_extend;
  end else if (busy_q) begin
    if (stall_counter != '0) begin
      stall_counter <= stall_counter - 1'b1;
    end else begin
      busy_q <= 1'b0;

      if (req_wr_en) begin
        case (req_data_size)
          BYTE: begin
            case (req_byte_offset)
              2'b00: mem[req_word_addr][7:0] <= req_wr_data[7:0];
              2'b01: mem[req_word_addr][15:8] <= req_wr_data[7:0];
              2'b10: mem[req_word_addr][23:16] <= req_wr_data[7:0];
              default: mem[req_word_addr][31:24] <= req_wr_data[7:0];
            endcase
          end
          HALF_WORD: begin // RISC RV32I is aligned, div by 2 for HALF_WORD, div by 4 for WORD
            if (req_byte_offset == 2'b00) mem[req_word_addr][15:0] <= req_wr_data[15:0];
            else if (req_byte_offset == 2'b10) mem[req_word_addr][31:16] <= req_wr_data[15:0];
          end
          WORD: begin
            if (req_byte_offset == 2'b00) mem[req_word_addr] <= req_wr_data;
          end
        endcase
      end else begin
        ram_rd_data <= mem[req_word_addr];
        ram_zero_extend <= req_zero_extend;
        ram_data_size <= req_data_size;
        ram_byte_offset <= req_byte_offset;
      end
    end
  end
end

// read logic - load (synchronous; matches BRAM read-port semantics)
// Output reg holds last loaded value across cycles where no read is issued,
// so MEM-stage data is still on dmem_rd_data when WB consumes it next cycle.
always_comb begin
  case (ram_data_size)
    BYTE: begin
      case (ram_byte_offset)
        2'b00: dmem_rd_data = ram_zero_extend ? {24'h0, ram_rd_data[7:0]} : {{24{ram_rd_data[7]}}, ram_rd_data[7:0]};
        2'b01: dmem_rd_data = ram_zero_extend ? {24'h0, ram_rd_data[15:8]} : {{24{ram_rd_data[15]}}, ram_rd_data[15:8]};
        2'b10: dmem_rd_data = ram_zero_extend ? {24'h0, ram_rd_data[23:16]} : {{24{ram_rd_data[23]}}, ram_rd_data[23:16]};
        default: dmem_rd_data = ram_zero_extend ? {24'h0, ram_rd_data[31:24]} : {{24{ram_rd_data[31]}}, ram_rd_data[31:24]};
      endcase
    end
    HALF_WORD: dmem_rd_data = ram_zero_extend ? 
    (ram_byte_offset[1] ? {16'h0, ram_rd_data[31:16]} : {16'h0, ram_rd_data[15:0]}) 
    : (ram_byte_offset[1] ? {{16{ram_rd_data[31]}}, ram_rd_data[31:16]} : {{16{ram_rd_data[15]}}, ram_rd_data[15:0]});
    WORD: dmem_rd_data = ram_rd_data;
  endcase
end

endmodule
